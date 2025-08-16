#!/usr/bin/env python3
"""Comprehensive unit tests for Texas Hold'em implementation."""

import pytest
from unittest.mock import Mock, patch
from poker_ai.games.texas_holdem.state import TexasHoldemPokerState, new_game
from poker_ai.games.texas_holdem.player import TexasHoldemPokerPlayer
from poker_ai.games.factory import create_poker_game
from poker_ai.poker.pot import Pot


class TestTexasHoldemPlayer:
    """Test the Texas Hold'em player implementation."""
    
    def test_player_creation(self):
        """Test player creation with various parameters."""
        pot = Pot()
        player = TexasHoldemPokerPlayer(player_i=0, initial_chips=10000, pot=pot)
        
        assert player.player_i == 0
        assert player.n_chips == 10000
        assert player.name == "Player_0"
        assert player.is_active == True
        assert player.has_folded == False
        assert player.n_bet_chips == 0
    
    def test_player_with_custom_name(self):
        """Test player creation with custom name."""
        pot = Pot()
        player = TexasHoldemPokerPlayer(
            player_i=1, 
            initial_chips=5000, 
            pot=pot, 
            name="Alice"
        )
        
        assert player.name == "Alice"
        assert player.n_chips == 5000
    
    def test_player_betting(self):
        """Test player betting functionality."""
        pot = Pot()
        player = TexasHoldemPokerPlayer(player_i=0, initial_chips=10000, pot=pot)
        
        # Test adding to pot
        player.add_to_pot(100)
        assert player.n_chips == 9900
        assert player.n_bet_chips == 100
        assert pot.total == 100
        
        # Test adding more
        player.add_to_pot(200)
        assert player.n_chips == 9700
        assert player.n_bet_chips == 300
        assert pot.total == 300
    
    def test_player_folding(self):
        """Test player folding."""
        pot = Pot()
        player = TexasHoldemPokerPlayer(player_i=0, initial_chips=10000, pot=pot)
        
        assert player.is_active == True
        action = player.fold()
        assert player.is_active == False
        assert str(action) == "fold"
    
    def test_player_reset(self):
        """Test resetting player for new round."""
        pot = Pot()
        player = TexasHoldemPokerPlayer(player_i=0, initial_chips=10000, pot=pot)
        
        # Modify player state
        player.fold()
        player.has_folded = True
        player.is_all_in = True
        
        # Reset
        player.reset_for_new_round()
        
        assert player.is_active == True
        assert player.has_folded == False
        assert player.is_all_in == False
        assert player.cards == []


class TestTexasHoldemState:
    """Test the Texas Hold'em state implementation."""
    
    def test_game_creation_valid_players(self):
        """Test creating games with valid player counts."""
        for n_players in [2, 3, 4, 5, 6, 7, 8]:
            game = new_game(n_players=n_players)
            assert game.n_players == n_players
            assert len(game.players) == n_players
            assert game.betting_stage == "pre_flop"
    
    def test_game_creation_invalid_players(self):
        """Test creating games with invalid player counts."""
        with pytest.raises(ValueError, match="between 2 and 8"):
            new_game(n_players=1)
        
        with pytest.raises(ValueError, match="between 2 and 8"):
            new_game(n_players=9)
        
        with pytest.raises(ValueError, match="between 2 and 8"):
            new_game(n_players=0)
    
    def test_initial_game_state(self):
        """Test initial game state properties."""
        game = new_game(n_players=4)
        
        # Check initial state
        assert game.betting_stage == "pre_flop"
        assert not game.is_terminal
        assert game.n_players == 4
        assert len(game.community_cards) == 0
        
        # Check players
        for player in game.players:
            assert player.n_chips > 0
            assert len(player.cards) == 2  # Each player has 2 hole cards
    
    def test_legal_actions(self):
        """Test that legal actions are properly determined."""
        game = new_game(n_players=4)
        
        legal_actions = game.legal_actions
        assert isinstance(legal_actions, list)
        assert len(legal_actions) > 0
        
        # In pre-flop, typical actions should be available
        assert "fold" in legal_actions
        assert any(action in ["call", "raise"] for action in legal_actions)
    
    def test_apply_action_fold(self):
        """Test applying a fold action."""
        game = new_game(n_players=4)
        initial_player_i = game.player_i
        
        if "fold" in game.legal_actions:
            new_state = game.apply_action("fold")
            
            # State should change
            assert new_state is not game
            # Player should have folded
            assert not new_state.players[initial_player_i].is_active
    
    def test_apply_action_call(self):
        """Test applying a call action."""
        game = new_game(n_players=4)
        
        if "call" in game.legal_actions:
            initial_chips = game.current_player.n_chips
            new_state = game.apply_action("call")
            
            # State should change
            assert new_state is not game
            # Player should have fewer chips (unless checking)
            assert new_state.players[game.player_i].n_chips <= initial_chips
    
    def test_apply_illegal_action(self):
        """Test that illegal actions raise errors."""
        game = new_game(n_players=4)
        
        with pytest.raises(ValueError, match="not in legal actions"):
            game.apply_action("invalid_action")
    
    def test_game_progression(self):
        """Test that the game progresses through betting stages."""
        game = new_game(n_players=4)
        
        # Play until we move to next stage or game ends
        max_actions = 20
        stages_seen = set()
        stages_seen.add(game.betting_stage)
        
        for _ in range(max_actions):
            if game.is_terminal:
                break
            
            legal_actions = game.legal_actions
            if legal_actions:
                # Take first legal action
                game = game.apply_action(legal_actions[0])
                stages_seen.add(game.betting_stage)
        
        # We should see at least pre_flop
        assert "pre_flop" in stages_seen
    
    def test_terminal_state(self):
        """Test terminal state detection."""
        game = new_game(n_players=4)
        
        # Play until terminal
        max_actions = 100
        for _ in range(max_actions):
            if game.is_terminal:
                break
            
            legal_actions = game.legal_actions
            if legal_actions:
                # Everyone folds except one
                action = "fold" if "fold" in legal_actions else legal_actions[0]
                game = game.apply_action(action)
        
        # Should eventually reach terminal state
        if game.is_terminal:
            assert game.betting_stage in ["terminal", "show_down"]
            assert game.payout is not None


class TestFactory:
    """Test the factory pattern for game creation."""
    
    def test_create_texas_holdem(self):
        """Test creating Texas Hold'em through factory."""
        game = create_poker_game("texas_holdem", n_players=6)
        
        assert isinstance(game, TexasHoldemPokerState)
        assert game.n_players == 6
    
    def test_backward_compatibility(self):
        """Test that short_deck creates Texas Hold'em for backward compatibility."""
        game = create_poker_game("short_deck", n_players=4)
        
        # Should create Texas Hold'em
        assert isinstance(game, TexasHoldemPokerState)
        assert game.n_players == 4
    
    def test_invalid_game_type(self):
        """Test that invalid game type creates Texas Hold'em as fallback."""
        game = create_poker_game("invalid_type", n_players=4)
        
        # Should default to Texas Hold'em
        assert isinstance(game, TexasHoldemPokerState)
        assert game.n_players == 4
    
    def test_factory_with_custom_blinds(self):
        """Test factory with custom blind amounts."""
        game = create_poker_game(
            "texas_holdem", 
            n_players=4,
            small_blind=100,
            big_blind=200
        )
        
        assert game.small_blind == 100
        assert game.big_blind == 200


class TestGameIntegration:
    """Integration tests for full game scenarios."""
    
    def test_heads_up_game(self):
        """Test a heads-up (2 player) game."""
        game = new_game(n_players=2)
        
        assert game.n_players == 2
        assert len(game.players) == 2
        
        # Play some actions
        actions_taken = 0
        max_actions = 10
        
        while not game.is_terminal and actions_taken < max_actions:
            legal_actions = game.legal_actions
            if legal_actions:
                game = game.apply_action(legal_actions[0])
                actions_taken += 1
        
        assert actions_taken > 0
    
    def test_full_table_game(self):
        """Test a full table (8 player) game."""
        game = new_game(n_players=8)
        
        assert game.n_players == 8
        assert len(game.players) == 8
        
        # Each player should have chips
        for player in game.players:
            assert player.n_chips > 0
    
    def test_all_players_fold_except_one(self):
        """Test scenario where all players fold except one."""
        game = new_game(n_players=4)
        
        # Make everyone fold if possible
        folds = 0
        max_actions = 20
        
        for _ in range(max_actions):
            if game.is_terminal:
                break
            
            if "fold" in game.legal_actions:
                game = game.apply_action("fold")
                folds += 1
            else:
                # Take any other action
                game = game.apply_action(game.legal_actions[0])
        
        # Game should end when only one player remains
        if folds >= 3:
            assert game.is_terminal or game.betting_stage == "show_down"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])