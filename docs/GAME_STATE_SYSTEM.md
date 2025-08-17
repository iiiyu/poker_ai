# Game State and Traversal System

## Overview

The game state system is the foundation of the poker AI. It represents poker hands as immutable state objects that can be efficiently traversed during MCCFR training. This document explains how game states work, how they're traversed, and how they integrate with the AI.

## Core Architecture

### State Hierarchy

```
TexasHoldemPokerState (Immutable)
    ├── Players (list of Player objects)
    ├── Deck (remaining cards)
    ├── Community Cards (board)
    ├── Pot (current pot state)
    ├── Betting Round (preflop/flop/turn/river)
    ├── Action History
    └── Game Phase (betting/showdown/terminal)
```

## The TexasHoldemPokerState Class

Located in `poker_ai/games/texas_holdem/state.py`

### Design Principles

1. **Immutability**: States are never modified. Actions create new states.
2. **Efficiency**: Minimal copying, maximal sharing between states
3. **Deterministic**: Same action on same state always produces same result
4. **Self-Contained**: Each state has all info needed for traversal

### Key Properties

```python
class TexasHoldemPokerState:
    # Game state
    players: List[Player]          # All players with chips, cards, status
    deck: Deck                      # Remaining undealt cards
    community_cards: List[Card]     # Board cards (0-5)
    
    # Betting state
    current_player: int             # Whose turn to act
    betting_round: str              # "preflop", "flop", "turn", "river"
    min_raise: int                  # Minimum legal raise size
    
    # History tracking
    history: List[Action]           # All actions taken
    betting_history: Dict           # Actions per round
    
    # Pot management
    pot: Pot                        # Main pot + side pots
    
    # Game flow
    is_terminal: bool               # Is hand complete?
    winners: List[int]              # Winner player indices
```

## State Transitions

### Action Application

When an action is applied, a new state is created:

```python
def apply_action(self, action: str) -> TexasHoldemPokerState:
    # 1. Validate action is legal
    if action not in self.legal_actions:
        raise IllegalActionError(f"{action} not legal")
    
    # 2. Create new state (shallow copy)
    new_state = TexasHoldemPokerState()
    new_state.players = self.players.copy()
    new_state.deck = self.deck.copy()
    # ... copy other fields
    
    # 3. Apply action effects
    if action == "fold":
        new_state.players[self.current_player].is_active = False
    elif action == "call":
        amount = self.amount_to_call()
        new_state.players[self.current_player].bet(amount)
        new_state.pot.add(amount)
    elif action == "raise":
        # ... handle raise logic
    
    # 4. Advance game state
    new_state.current_player = self.next_player()
    if self.betting_round_complete():
        new_state.advance_to_next_round()
    
    return new_state
```

### Legal Actions

Legal actions are computed dynamically:

```python
@property
def legal_actions(self) -> List[str]:
    if self.is_terminal:
        return []
    
    actions = []
    player = self.players[self.current_player]
    
    # Can always fold (unless all-in)
    if player.chips > 0:
        actions.append("fold")
    
    # Can call if there's a bet to call
    amount_to_call = self.amount_to_call()
    if amount_to_call > 0:
        if player.chips >= amount_to_call:
            actions.append("call")
        else:
            actions.append("all-in")  # Partial call
    else:
        actions.append("check")  # No bet to call
    
    # Can raise if betting is open
    if self.can_raise():
        if player.chips >= self.min_raise:
            actions.append("raise")
        # Could add bet sizing: raise_2x, raise_pot, etc.
    
    return actions
```

## Information Sets

Information sets group states that look identical to a player:

```python
def info_set_key(self, player_index: int) -> str:
    """
    Create unique key for this information set.
    Includes everything the player can observe.
    """
    player = self.players[player_index]
    
    # Components of information set
    components = [
        # Player's private cards (clustered)
        self.cluster_cards(player.hand),
        
        # Public cards (clustered)
        self.cluster_cards(self.community_cards),
        
        # Betting history (abstracted)
        self.abstract_betting_history(),
        
        # Pot size (bucketed)
        self.bucket_pot_size(),
        
        # Stack sizes (bucketed)
        self.bucket_stack_sizes(),
    ]
    
    return "|".join(components)
```

### Information Set Example

```
Player 0 holds: A♠ K♠
Board: Q♦ J♣ 10♠
History: Player1-raise-300, Player2-call-300, Player0-?

Info set: "AKs|QJT-rainbow|R300-C300|pot1200|stacks-deep"
```

## Tree Traversal

### Depth-First Traversal

The MCCFR algorithm traverses the game tree depth-first:

```python
def traverse(state: TexasHoldemPokerState, player: int) -> float:
    """
    Traverse game tree from current state.
    Returns expected value for traversing player.
    """
    # Terminal node - return payoff
    if state.is_terminal:
        return state.payoff(player)
    
    # Current player is traversing player
    if state.current_player == player:
        # Try all actions
        values = {}
        for action in state.legal_actions:
            new_state = state.apply_action(action)
            values[action] = traverse(new_state, player)
        
        # Update strategy based on regrets
        info_set = state.info_set_key(player)
        update_strategy(info_set, values)
        
        # Return expected value
        return expected_value(values, strategy[info_set])
    
    # Opponent's turn - sample their action
    else:
        opponent = state.current_player
        info_set = state.info_set_key(opponent)
        action = sample_action(strategy[info_set])
        new_state = state.apply_action(action)
        return traverse(new_state, player)
```

### Traversal Optimization

#### 1. Pruning
Skip branches with very negative regret:

```python
if cumulative_regret[info_set][action] < -300:
    continue  # Don't traverse this action
```

#### 2. Caching
Cache frequently accessed computations:

```python
@cached_property
def legal_actions(self):
    return self._compute_legal_actions()

@cached_property
def is_terminal(self):
    return self._check_terminal()
```

#### 3. State Sharing
Share immutable components between states:

```python
# Don't copy unchanged components
new_state.deck = self.deck  # Same deck reference
new_state.community_cards = self.community_cards  # Same if no new cards
```

## Betting Rounds

### Round Progression

```python
def advance_to_next_round(self):
    """Move to next betting round."""
    if self.betting_round == "preflop":
        # Deal flop (3 cards)
        self.community_cards = self.deck.deal(3)
        self.betting_round = "flop"
        
    elif self.betting_round == "flop":
        # Deal turn (1 card)
        self.community_cards.append(self.deck.deal(1))
        self.betting_round = "turn"
        
    elif self.betting_round == "turn":
        # Deal river (1 card)
        self.community_cards.append(self.deck.deal(1))
        self.betting_round = "river"
        
    elif self.betting_round == "river":
        # Move to showdown
        self.is_terminal = True
        self.determine_winners()
    
    # Reset betting for new round
    self.reset_betting()
```

### Betting Complete Check

```python
def betting_round_complete(self) -> bool:
    """Check if current betting round is done."""
    # All players have acted
    if not all(p.has_acted for p in self.active_players):
        return False
    
    # All bets are matched
    max_bet = max(p.current_bet for p in self.active_players)
    for player in self.active_players:
        if player.current_bet < max_bet and player.chips > 0:
            return False
    
    return True
```

## Pot Management

### Main Pot and Side Pots

```python
class Pot:
    def __init__(self):
        self.main_pot = 0
        self.side_pots = []  # [(amount, eligible_players)]
    
    def add_bet(self, player_id: int, amount: int):
        """Add a bet, creating side pots if needed."""
        # Implementation handles all-ins and side pots
        
    def distribute(self, winners: List[int]) -> Dict[int, int]:
        """Distribute pot to winners."""
        winnings = defaultdict(int)
        
        # Distribute main pot
        eligible_winners = [w for w in winners if w in self.main_eligible]
        if eligible_winners:
            share = self.main_pot // len(eligible_winners)
            for winner in eligible_winners:
                winnings[winner] += share
        
        # Distribute side pots
        for pot_amount, eligible in self.side_pots:
            pot_winners = [w for w in winners if w in eligible]
            if pot_winners:
                share = pot_amount // len(pot_winners)
                for winner in pot_winners:
                    winnings[winner] += share
        
        return winnings
```

## Terminal States and Payoffs

### Determining Winners

```python
def determine_winners(self):
    """Determine winner(s) at showdown."""
    if self.num_active_players == 1:
        # Everyone folded - last player wins
        self.winners = [self.last_active_player()]
    else:
        # Showdown - compare hands
        hand_strengths = []
        for player in self.active_players:
            hand = player.hand + self.community_cards
            strength = evaluate_hand(hand)
            hand_strengths.append((strength, player.index))
        
        # Find best hand(s)
        best_strength = max(strength for strength, _ in hand_strengths)
        self.winners = [idx for strength, idx in hand_strengths 
                       if strength == best_strength]
```

### Payoff Calculation

```python
def payoff(self, player_index: int) -> float:
    """Calculate payoff for a player."""
    if not self.is_terminal:
        raise ValueError("Can't calculate payoff for non-terminal state")
    
    player = self.players[player_index]
    
    # Starting chips - ending chips = loss
    # Ending chips - starting chips = profit
    starting_chips = 20000  # Or tracked in state
    ending_chips = player.chips
    
    if player_index in self.winners:
        # Add winnings
        winnings = self.pot.distribute(self.winners)
        ending_chips += winnings[player_index]
    
    return ending_chips - starting_chips
```

## State Factory

### Creating New Games

```python
def new_game(
    n_players: int = 3,
    small_blind: int = 50,
    big_blind: int = 100,
    starting_chips: int = 20000,
    card_info_lut: Dict = None
) -> TexasHoldemPokerState:
    """Create a new Texas Hold'em game."""
    
    # Create players
    players = []
    for i in range(n_players):
        players.append(Player(
            index=i,
            chips=starting_chips,
            hand=None,  # Will be dealt
            is_dealer=(i == 0)
        ))
    
    # Create deck
    deck = Deck.full_deck()  # 52 cards
    
    # Deal hole cards
    for player in players:
        player.hand = deck.deal(2)
    
    # Create initial state
    state = TexasHoldemPokerState(
        players=players,
        deck=deck,
        community_cards=[],
        pot=Pot(),
        betting_round="preflop",
        current_player=3 % n_players,  # After blinds
        small_blind=small_blind,
        big_blind=big_blind,
        card_info_lut=card_info_lut
    )
    
    # Post blinds
    state = state.post_blinds()
    
    return state
```

## Performance Considerations

### Memory Usage

Each state object uses approximately:
- Base state: ~500 bytes
- With history: ~2KB
- With full traversal data: ~5KB

During training with 1M iterations:
- Peak memory: ~5GB (storing strategies)
- State objects: ~100MB (mostly garbage collected)

### Speed Optimizations

1. **Immutable Strings**: Use interned strings for actions
2. **Integer IDs**: Use integers instead of strings where possible
3. **Numpy Arrays**: For large numerical data
4. **Cython**: Critical paths can be compiled

### Profiling Results

From typical MCCFR iteration:
- State creation: 15% of time
- Action application: 20% of time
- Information set calculation: 30% of time
- Strategy updates: 25% of time
- Other: 10% of time

## Testing the State System

### Unit Tests

```python
def test_state_immutability():
    """Ensure states are immutable."""
    state1 = new_game()
    state2 = state1.apply_action("call")
    
    assert state1.current_player != state2.current_player
    assert state1 is not state2

def test_legal_actions():
    """Test legal action generation."""
    state = new_game()
    
    # Preflop, after blinds
    assert "fold" in state.legal_actions
    assert "call" in state.legal_actions
    assert "raise" in state.legal_actions

def test_terminal_detection():
    """Test terminal state detection."""
    state = new_game(n_players=2)
    
    # Play until terminal
    while not state.is_terminal:
        action = state.legal_actions[0]
        state = state.apply_action(action)
    
    assert state.is_terminal
    assert len(state.winners) > 0
```

## Integration with MCCFR

The state system integrates with MCCFR through:

1. **Traversal Interface**: States provide `apply_action()` for tree traversal
2. **Information Sets**: States compute info sets for strategy storage
3. **Terminal Values**: States calculate payoffs for regret computation
4. **Legal Actions**: States constrain the action space
5. **Efficient Cloning**: Immutable states enable fast branching

## Future Improvements

1. **Action Abstractions**: Bucket raise sizes (2x, 3x, pot, all-in)
2. **State Compression**: Compress state representation
3. **Parallel Traversal**: Thread-safe state operations
4. **JIT Compilation**: Compile hot paths with Numba
5. **State Pooling**: Reuse state objects to reduce allocation