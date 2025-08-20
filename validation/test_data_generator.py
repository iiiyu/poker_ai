"""
Generate comprehensive test datasets for validation.

This module creates golden datasets from the Python implementation
that can be used to validate the Zig implementation.
"""

import json
import pickle
import random
from pathlib import Path
from typing import List, Dict, Any, Tuple, Iterator
import itertools
import sys

# Add project root to path
sys.path.append(str(Path(__file__).parent.parent))

try:
    from poker_ai.poker.evaluation.evaluator import Evaluator
    from poker_ai.poker.evaluation.eval_card import EvaluationCard
    from poker_ai.poker.evaluation.deck import Deck
    from poker_ai.poker.actions import Action
    from poker_ai.games.game import Game
    PYTHON_AVAILABLE = True
except ImportError as e:
    print(f"Warning: Python poker_ai not available: {e}")
    PYTHON_AVAILABLE = False


class TestDataGenerator:
    """Generate comprehensive test datasets for validation."""
    
    def __init__(self, output_dir: Path = None):
        self.output_dir = output_dir or Path(__file__).parent / "data"
        self.output_dir.mkdir(exist_ok=True)
        
        if PYTHON_AVAILABLE:
            self.evaluator = Evaluator()
            self.deck = Deck()
        else:
            self.evaluator = None
            self.deck = None
    
    def generate_hand_evaluation_dataset(self, num_samples: int = 10000) -> Dict[str, Any]:
        """Generate comprehensive hand evaluation test cases."""
        if not PYTHON_AVAILABLE:
            return {"error": "Python not available"}
        
        print(f"Generating {num_samples} hand evaluation test cases...")
        
        test_cases = []
        
        # 1. Systematic coverage of hand types
        hand_types = [
            ("royal_flush", self._generate_royal_flush_hands),
            ("straight_flush", self._generate_straight_flush_hands),
            ("four_of_kind", self._generate_four_of_kind_hands),
            ("full_house", self._generate_full_house_hands),
            ("flush", self._generate_flush_hands),
            ("straight", self._generate_straight_hands),
            ("three_of_kind", self._generate_three_of_kind_hands),
            ("two_pair", self._generate_two_pair_hands),
            ("pair", self._generate_pair_hands),
            ("high_card", self._generate_high_card_hands),
        ]
        
        samples_per_type = num_samples // len(hand_types)
        
        for hand_type, generator in hand_types:
            print(f"  Generating {samples_per_type} {hand_type} hands...")
            
            for hand_cards in generator(samples_per_type):
                try:
                    # Convert to evaluation cards
                    eval_cards = [EvaluationCard.new(card) for card in hand_cards]
                    
                    # Evaluate with Python
                    if len(eval_cards) == 7:
                        rank = self.evaluator.evaluate(eval_cards[:5], eval_cards[5:])
                    else:
                        rank = self.evaluator.evaluate(eval_cards, [])
                    
                    # Get hand class
                    hand_class = self.evaluator.get_rank_class(rank)
                    hand_class_name = self.evaluator.class_to_string(hand_class)
                    
                    test_cases.append({
                        "cards": hand_cards,
                        "rank": rank,
                        "hand_class": hand_class,
                        "hand_class_name": hand_class_name,
                        "expected_type": hand_type
                    })
                    
                except Exception as e:
                    print(f"    Error evaluating {hand_cards}: {e}")
                    continue
        
        # 2. Random sampling for edge cases
        print(f"  Generating random hands...")
        for _ in range(num_samples // 10):  # 10% random
            self.deck.shuffle()
            hand_cards = [str(card) for card in self.deck.draw(7)]
            
            try:
                eval_cards = [EvaluationCard.new(card) for card in hand_cards]
                rank = self.evaluator.evaluate(eval_cards[:5], eval_cards[5:])
                hand_class = self.evaluator.get_rank_class(rank)
                hand_class_name = self.evaluator.class_to_string(hand_class)
                
                test_cases.append({
                    "cards": hand_cards,
                    "rank": rank,
                    "hand_class": hand_class,
                    "hand_class_name": hand_class_name,
                    "expected_type": "random"
                })
            except Exception as e:
                continue
        
        dataset = {
            "description": "Comprehensive hand evaluation test dataset",
            "num_cases": len(test_cases),
            "test_cases": test_cases,
            "metadata": {
                "python_evaluator": True,
                "samples_per_type": samples_per_type,
                "total_requested": num_samples
            }
        }
        
        # Save dataset
        output_file = self.output_dir / "hand_evaluation_dataset.json"
        with open(output_file, 'w') as f:
            json.dump(dataset, f, indent=2)
        
        print(f"Hand evaluation dataset saved: {output_file}")
        print(f"Generated {len(test_cases)} valid test cases")
        
        return dataset
    
    def generate_game_state_dataset(self, num_games: int = 1000) -> Dict[str, Any]:
        """Generate game state transition test cases."""
        if not PYTHON_AVAILABLE:
            return {"error": "Python not available"}
        
        print(f"Generating {num_games} game state test cases...")
        
        test_cases = []
        
        for game_idx in range(num_games):
            try:
                # Create a game instance
                game = Game(num_players=6, buyin=1000, big_blind=20, small_blind=10)
                
                # Record initial state
                initial_state = self._capture_game_state(game)
                
                game_transitions = []
                turn_count = 0
                
                while not game.is_over and turn_count < 100:  # Prevent infinite loops
                    # Get current state
                    current_state = self._capture_game_state(game)
                    
                    # Get legal actions
                    legal_actions = game.get_legal_actions()
                    
                    if not legal_actions:
                        break
                    
                    # Choose random legal action
                    action = random.choice(legal_actions)
                    
                    # Apply action
                    try:
                        game.apply_action(action)
                        
                        # Record transition
                        new_state = self._capture_game_state(game)
                        
                        game_transitions.append({
                            "turn": turn_count,
                            "before_state": current_state,
                            "action": self._serialize_action(action),
                            "after_state": new_state,
                            "legal_actions": [self._serialize_action(a) for a in legal_actions]
                        })
                        
                        turn_count += 1
                        
                    except Exception as e:
                        print(f"    Error applying action {action}: {e}")
                        break
                
                test_cases.append({
                    "game_id": game_idx,
                    "initial_state": initial_state,
                    "transitions": game_transitions,
                    "final_state": self._capture_game_state(game),
                    "game_over": game.is_over,
                    "winners": game.get_winners() if hasattr(game, 'get_winners') else []
                })
                
                if (game_idx + 1) % 100 == 0:
                    print(f"  Generated {game_idx + 1} games...")
                    
            except Exception as e:
                print(f"  Error in game {game_idx}: {e}")
                continue
        
        dataset = {
            "description": "Game state transition test dataset",
            "num_games": len(test_cases),
            "test_cases": test_cases,
            "metadata": {
                "num_players": 6,
                "buyin": 1000,
                "blinds": {"small": 10, "big": 20}
            }
        }
        
        # Save dataset
        output_file = self.output_dir / "game_state_dataset.json"
        with open(output_file, 'w') as f:
            json.dump(dataset, f, indent=2)
        
        print(f"Game state dataset saved: {output_file}")
        print(f"Generated {len(test_cases)} valid games")
        
        return dataset
    
    def generate_clustering_dataset(self, num_samples: int = 5000) -> Dict[str, Any]:
        """Generate clustering test cases."""
        if not PYTHON_AVAILABLE:
            return {"error": "Python not available"}
        
        print(f"Generating {num_samples} clustering test cases...")
        
        test_cases = []
        
        for sample_idx in range(num_samples):
            try:
                # Generate random preflop, flop, turn, river
                self.deck.shuffle()
                
                # Preflop: 2 hole cards
                hole_cards = [str(card) for card in self.deck.draw(2)]
                
                # Flop: 3 community cards  
                flop = [str(card) for card in self.deck.draw(3)]
                
                # Turn: 1 more community card
                turn = [str(card) for card in self.deck.draw(1)]
                
                # River: 1 more community card
                river = [str(card) for card in self.deck.draw(1)]
                
                # Calculate EHS (Expected Hand Strength) at each stage
                preflop_cards = hole_cards
                flop_cards = hole_cards + flop
                turn_cards = hole_cards + flop + turn
                river_cards = hole_cards + flop + turn + river
                
                # This would require implementing EHS calculation
                # For now, we'll use hand evaluation as a proxy
                eval_cards = [EvaluationCard.new(card) for card in river_cards]
                final_rank = self.evaluator.evaluate(eval_cards[:5], eval_cards[5:] if len(eval_cards) > 5 else [])
                
                test_cases.append({
                    "sample_id": sample_idx,
                    "hole_cards": hole_cards,
                    "flop": flop,
                    "turn": turn,
                    "river": river,
                    "stages": {
                        "preflop": preflop_cards,
                        "flop": flop_cards,
                        "turn": turn_cards,
                        "river": river_cards
                    },
                    "final_rank": final_rank,
                    "final_hand_class": self.evaluator.get_rank_class(final_rank)
                })
                
                if (sample_idx + 1) % 1000 == 0:
                    print(f"  Generated {sample_idx + 1} samples...")
                    
            except Exception as e:
                print(f"  Error in sample {sample_idx}: {e}")
                continue
        
        dataset = {
            "description": "Clustering test dataset",
            "num_samples": len(test_cases),
            "test_cases": test_cases,
            "metadata": {
                "stages": ["preflop", "flop", "turn", "river"],
                "clustering_features": ["EHS", "hand_strength", "potential"]
            }
        }
        
        # Save dataset
        output_file = self.output_dir / "clustering_dataset.json"
        with open(output_file, 'w') as f:
            json.dump(dataset, f, indent=2)
        
        print(f"Clustering dataset saved: {output_file}")
        print(f"Generated {len(test_cases)} valid samples")
        
        return dataset
    
    def _generate_royal_flush_hands(self, count: int) -> Iterator[List[str]]:
        """Generate royal flush hands."""
        suits = ['s', 'h', 'd', 'c']
        royal_ranks = ['T', 'J', 'Q', 'K', 'A']
        
        for _ in range(count):
            suit = random.choice(suits)
            royal_cards = [f"{rank}{suit}" for rank in royal_ranks]
            
            # Add 2 random cards from other suits
            remaining_cards = []
            for s in suits:
                if s != suit:
                    for rank in '23456789TJQKA':
                        remaining_cards.append(f"{rank}{s}")
            
            extra_cards = random.sample(remaining_cards, 2)
            hand = royal_cards + extra_cards
            random.shuffle(hand)
            yield hand
    
    def _generate_straight_flush_hands(self, count: int) -> Iterator[List[str]]:
        """Generate straight flush hands."""
        suits = ['s', 'h', 'd', 'c']
        
        # Possible straights (low card)
        straight_starts = [1, 2, 3, 4, 5, 6, 7, 8, 9]  # A-5 through 9-K
        
        for _ in range(count):
            suit = random.choice(suits)
            start = random.choice(straight_starts)
            
            if start == 1:  # A-5 straight (wheel)
                ranks = [1, 2, 3, 4, 5]  # A, 2, 3, 4, 5
                rank_strs = ['A', '2', '3', '4', '5']
            else:
                ranks = list(range(start, start + 5))
                rank_strs = []
                for r in ranks:
                    if r <= 9:
                        rank_strs.append(str(r + 1))  # Convert to card rank
                    elif r == 10:
                        rank_strs.append('T')
                    elif r == 11:
                        rank_strs.append('J')
                    elif r == 12:
                        rank_strs.append('Q')
                    elif r == 13:
                        rank_strs.append('K')
                    elif r == 14:
                        rank_strs.append('A')
            
            straight_cards = [f"{rank}{suit}" for rank in rank_strs]
            
            # Add 2 random non-matching cards
            remaining_cards = []
            for s in suits:
                for rank in '23456789TJQKA':
                    card = f"{rank}{s}"
                    if card not in straight_cards:
                        remaining_cards.append(card)
            
            extra_cards = random.sample(remaining_cards, 2)
            hand = straight_cards + extra_cards
            random.shuffle(hand)
            yield hand
    
    def _generate_four_of_kind_hands(self, count: int) -> Iterator[List[str]]:
        """Generate four of a kind hands."""
        ranks = '23456789TJQKA'
        suits = ['s', 'h', 'd', 'c']
        
        for _ in range(count):
            # Choose rank for quads
            quad_rank = random.choice(ranks)
            quad_cards = [f"{quad_rank}{suit}" for suit in suits]
            
            # Choose 3 random other cards
            remaining_cards = []
            for rank in ranks:
                if rank != quad_rank:
                    for suit in suits:
                        remaining_cards.append(f"{rank}{suit}")
            
            extra_cards = random.sample(remaining_cards, 3)
            hand = quad_cards + extra_cards
            random.shuffle(hand)
            yield hand
    
    def _generate_full_house_hands(self, count: int) -> Iterator[List[str]]:
        """Generate full house hands."""
        ranks = '23456789TJQKA'
        suits = ['s', 'h', 'd', 'c']
        
        for _ in range(count):
            # Choose ranks for trips and pair
            trip_rank = random.choice(ranks)
            remaining_ranks = [r for r in ranks if r != trip_rank]
            pair_rank = random.choice(remaining_ranks)
            
            # Generate trips
            trip_suits = random.sample(suits, 3)
            trip_cards = [f"{trip_rank}{suit}" for suit in trip_suits]
            
            # Generate pair
            pair_suits = random.sample(suits, 2)
            pair_cards = [f"{pair_rank}{suit}" for suit in pair_suits]
            
            # Add 2 random other cards
            remaining_cards = []
            for rank in ranks:
                if rank not in [trip_rank, pair_rank]:
                    for suit in suits:
                        remaining_cards.append(f"{rank}{suit}")
            
            extra_cards = random.sample(remaining_cards, 2)
            hand = trip_cards + pair_cards + extra_cards
            random.shuffle(hand)
            yield hand
    
    def _generate_flush_hands(self, count: int) -> Iterator[List[str]]:
        """Generate flush hands."""
        suits = ['s', 'h', 'd', 'c']
        ranks = '23456789TJQKA'
        
        for _ in range(count):
            # Choose suit for flush
            flush_suit = random.choice(suits)
            
            # Choose 5 random ranks (avoid straights)
            flush_ranks = random.sample(list(ranks), 5)
            
            # Check if it's a straight and regenerate if so
            rank_values = []
            for rank in flush_ranks:
                if rank == 'A':
                    rank_values.append(14)
                elif rank == 'K':
                    rank_values.append(13)
                elif rank == 'Q':
                    rank_values.append(12)
                elif rank == 'J':
                    rank_values.append(11)
                elif rank == 'T':
                    rank_values.append(10)
                else:
                    rank_values.append(int(rank))
            
            rank_values.sort()
            
            # Check for straight
            is_straight = True
            for i in range(1, len(rank_values)):
                if rank_values[i] != rank_values[i-1] + 1:
                    is_straight = False
                    break
            
            # Check for A-5 straight
            if rank_values == [2, 3, 4, 5, 14]:
                is_straight = True
            
            if is_straight:
                # Regenerate to avoid straight flush
                flush_ranks = random.sample(list(ranks), 5)
            
            flush_cards = [f"{rank}{flush_suit}" for rank in flush_ranks]
            
            # Add 2 cards from other suits
            remaining_cards = []
            for suit in suits:
                if suit != flush_suit:
                    for rank in ranks:
                        remaining_cards.append(f"{rank}{suit}")
            
            extra_cards = random.sample(remaining_cards, 2)
            hand = flush_cards + extra_cards
            random.shuffle(hand)
            yield hand
    
    def _generate_straight_hands(self, count: int) -> Iterator[List[str]]:
        """Generate straight hands (non-flush)."""
        suits = ['s', 'h', 'd', 'c']
        straight_starts = [1, 2, 3, 4, 5, 6, 7, 8, 9]
        
        for _ in range(count):
            start = random.choice(straight_starts)
            
            if start == 1:  # A-5 straight
                ranks = ['A', '2', '3', '4', '5']
            else:
                rank_nums = list(range(start, start + 5))
                ranks = []
                for r in rank_nums:
                    if r <= 9:
                        ranks.append(str(r + 1))
                    elif r == 10:
                        ranks.append('T')
                    elif r == 11:
                        ranks.append('J')
                    elif r == 12:
                        ranks.append('Q')
                    elif r == 13:
                        ranks.append('K')
                    elif r == 14:
                        ranks.append('A')
            
            # Choose suits ensuring it's not a flush
            straight_cards = []
            chosen_suits = []
            
            for rank in ranks:
                suit = random.choice(suits)
                straight_cards.append(f"{rank}{suit}")
                chosen_suits.append(suit)
            
            # Ensure not all same suit (not a flush)
            if len(set(chosen_suits)) == 1:
                # Change one suit
                idx = random.randint(0, 4)
                other_suits = [s for s in suits if s != chosen_suits[0]]
                new_suit = random.choice(other_suits)
                straight_cards[idx] = f"{ranks[idx]}{new_suit}"
            
            # Add 2 random cards
            remaining_cards = []
            for rank in '23456789TJQKA':
                if rank not in ranks:
                    for suit in suits:
                        remaining_cards.append(f"{rank}{suit}")
            
            extra_cards = random.sample(remaining_cards, 2)
            hand = straight_cards + extra_cards
            random.shuffle(hand)
            yield hand
    
    def _generate_three_of_kind_hands(self, count: int) -> Iterator[List[str]]:
        """Generate three of a kind hands."""
        ranks = '23456789TJQKA'
        suits = ['s', 'h', 'd', 'c']
        
        for _ in range(count):
            # Choose rank for trips
            trip_rank = random.choice(ranks)
            trip_suits = random.sample(suits, 3)
            trip_cards = [f"{trip_rank}{suit}" for suit in trip_suits]
            
            # Choose 4 other cards with different ranks
            remaining_ranks = [r for r in ranks if r != trip_rank]
            other_ranks = random.sample(remaining_ranks, 4)
            
            other_cards = []
            for rank in other_ranks:
                suit = random.choice(suits)
                other_cards.append(f"{rank}{suit}")
            
            hand = trip_cards + other_cards
            random.shuffle(hand)
            yield hand
    
    def _generate_two_pair_hands(self, count: int) -> Iterator[List[str]]:
        """Generate two pair hands."""
        ranks = '23456789TJQKA'
        suits = ['s', 'h', 'd', 'c']
        
        for _ in range(count):
            # Choose 2 ranks for pairs
            pair_ranks = random.sample(list(ranks), 2)
            
            pair_cards = []
            for rank in pair_ranks:
                pair_suits = random.sample(suits, 2)
                for suit in pair_suits:
                    pair_cards.append(f"{rank}{suit}")
            
            # Choose 3 other cards with different ranks
            remaining_ranks = [r for r in ranks if r not in pair_ranks]
            other_ranks = random.sample(remaining_ranks, 3)
            
            other_cards = []
            for rank in other_ranks:
                suit = random.choice(suits)
                other_cards.append(f"{rank}{suit}")
            
            hand = pair_cards + other_cards
            random.shuffle(hand)
            yield hand
    
    def _generate_pair_hands(self, count: int) -> Iterator[List[str]]:
        """Generate one pair hands."""
        ranks = '23456789TJQKA'
        suits = ['s', 'h', 'd', 'c']
        
        for _ in range(count):
            # Choose rank for pair
            pair_rank = random.choice(ranks)
            pair_suits = random.sample(suits, 2)
            pair_cards = [f"{pair_rank}{suit}" for suit in pair_suits]
            
            # Choose 5 other cards with different ranks
            remaining_ranks = [r for r in ranks if r != pair_rank]
            other_ranks = random.sample(remaining_ranks, 5)
            
            other_cards = []
            for rank in other_ranks:
                suit = random.choice(suits)
                other_cards.append(f"{rank}{suit}")
            
            hand = pair_cards + other_cards
            random.shuffle(hand)
            yield hand
    
    def _generate_high_card_hands(self, count: int) -> Iterator[List[str]]:
        """Generate high card hands."""
        ranks = '23456789TJQKA'
        suits = ['s', 'h', 'd', 'c']
        
        for _ in range(count):
            # Choose 7 different ranks
            chosen_ranks = random.sample(list(ranks), 7)
            
            hand = []
            for rank in chosen_ranks:
                suit = random.choice(suits)
                hand.append(f"{rank}{suit}")
            
            random.shuffle(hand)
            yield hand
    
    def _capture_game_state(self, game) -> Dict[str, Any]:
        """Capture current game state."""
        try:
            return {
                "current_player": game.current_player if hasattr(game, 'current_player') else None,
                "pot": game.pot if hasattr(game, 'pot') else 0,
                "community_cards": [str(card) for card in game.board] if hasattr(game, 'board') else [],
                "round": game.round if hasattr(game, 'round') else 0,
                "players_in_hand": len([p for p in game.players if not p.folded]) if hasattr(game, 'players') else 0,
                "is_over": game.is_over if hasattr(game, 'is_over') else False
            }
        except:
            return {"error": "Could not capture game state"}
    
    def _serialize_action(self, action) -> Dict[str, Any]:
        """Serialize a poker action."""
        try:
            return {
                "type": action.action_type if hasattr(action, 'action_type') else str(action),
                "amount": action.amount if hasattr(action, 'amount') else 0,
                "player": action.player if hasattr(action, 'player') else None
            }
        except:
            return {"type": str(action), "amount": 0, "player": None}
    
    def generate_all_datasets(self) -> Dict[str, Any]:
        """Generate all test datasets."""
        if not PYTHON_AVAILABLE:
            print("❌ Cannot generate datasets - Python poker_ai not available")
            return {"error": "Python not available"}
        
        print("🔄 Generating comprehensive validation datasets...")
        
        results = {}
        
        try:
            results["hand_evaluation"] = self.generate_hand_evaluation_dataset(10000)
        except Exception as e:
            print(f"❌ Failed to generate hand evaluation dataset: {e}")
            results["hand_evaluation"] = {"error": str(e)}
        
        try:
            results["game_states"] = self.generate_game_state_dataset(1000)
        except Exception as e:
            print(f"❌ Failed to generate game state dataset: {e}")
            results["game_states"] = {"error": str(e)}
        
        try:
            results["clustering"] = self.generate_clustering_dataset(5000)
        except Exception as e:
            print(f"❌ Failed to generate clustering dataset: {e}")
            results["clustering"] = {"error": str(e)}
        
        # Save summary
        summary_file = self.output_dir / "dataset_summary.json"
        with open(summary_file, 'w') as f:
            json.dump(results, f, indent=2, default=str)
        
        print(f"✅ Dataset generation complete. Summary saved: {summary_file}")
        return results


def main():
    """Generate all test datasets."""
    generator = TestDataGenerator()
    results = generator.generate_all_datasets()
    
    if "error" not in results:
        print("✅ All datasets generated successfully!")
    else:
        print("⚠️  Some datasets failed to generate")
        return 1
    
    return 0


if __name__ == "__main__":
    sys.exit(main())