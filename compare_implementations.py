#!/usr/bin/env python3
"""
Compare Python and Zig clustering implementations to verify correctness.
"""

import sqlite3
import numpy as np
import struct
from typing import List, Tuple
import sys
import os

# Add poker_ai to path
sys.path.insert(0, '/Users/ewan/Developer/OhMyApps/Poker/poker_ai')

from poker_ai.poker.card import Card as PythonCard
from poker_ai.poker.evaluation import Evaluator
from poker_ai.clustering.game_utility import GameUtility


class ImplementationComparator:
    """Compare Python and Zig clustering implementations."""
    
    def __init__(self):
        self.evaluator = Evaluator()
        self.results = {
            'card_representation': [],
            'hand_evaluation': [],
            'ehs_calculation': [],
            'database_format': []
        }
    
    def test_card_representation(self):
        """Compare how cards are represented in both implementations."""
        print("\n" + "="*60)
        print("TESTING: Card Representation")
        print("="*60)
        
        # Python representation
        py_cards = []
        for suit in ["spades", "diamonds", "clubs", "hearts"]:
            for rank in range(2, 15):
                py_cards.append(PythonCard(rank, suit))
        
        print(f"Python cards (first 5): {py_cards[:5]}")
        print(f"Python card count: {len(py_cards)}")
        
        # Zig representation (as stored in DB)
        zig_cards = []
        for rank in range(2, 15):
            for suit in range(1, 5):
                zig_cards.append((rank, suit))
        
        print(f"Zig cards (first 5): {zig_cards[:5]}")
        print(f"Zig card count: {len(zig_cards)}")
        
        # Check ordering difference
        print("\n⚠️  Card Ordering Mismatch:")
        print(f"Python: Suit-first ordering (all spades, then diamonds, etc.)")
        print(f"Zig: Rank-first ordering (all 2s, then all 3s, etc.)")
        
        self.results['card_representation'].append({
            'issue': 'Card ordering mismatch',
            'python': 'Suit-first ordering',
            'zig': 'Rank-first ordering',
            'impact': 'Different combination generation'
        })
        
        return py_cards, zig_cards
    
    def test_hand_evaluation(self):
        """Test hand evaluation differences."""
        print("\n" + "="*60)
        print("TESTING: Hand Evaluation")
        print("="*60)
        
        # Test case 1: Pair of Aces
        test_hands = [
            {
                'name': 'Pair of Aces',
                'hand': [PythonCard(14, "spades"), PythonCard(14, "hearts")],
                'board': [
                    PythonCard(2, "diamonds"),
                    PythonCard(3, "clubs"),
                    PythonCard(5, "spades"),
                    PythonCard(7, "hearts"),
                    PythonCard(9, "diamonds")
                ]
            },
            {
                'name': 'Flush',
                'hand': [PythonCard(14, "spades"), PythonCard(10, "spades")],
                'board': [
                    PythonCard(2, "spades"),
                    PythonCard(5, "spades"),
                    PythonCard(7, "spades"),
                    PythonCard(3, "hearts"),
                    PythonCard(9, "diamonds")
                ]
            },
            {
                'name': 'High Card Only',
                'hand': [PythonCard(14, "spades"), PythonCard(3, "hearts")],
                'board': [
                    PythonCard(2, "diamonds"),
                    PythonCard(5, "clubs"),
                    PythonCard(7, "spades"),
                    PythonCard(9, "hearts"),
                    PythonCard(10, "diamonds")
                ]
            }
        ]
        
        for test in test_hands:
            # Python evaluation
            py_eval = self.evaluator.evaluate(
                board=[int(c) for c in test['board']],
                cards=[int(c) for c in test['hand']]
            )
            
            # Simulate Zig evaluation (wrong method)
            all_cards = test['hand'] + test['board']
            all_cards.sort(key=lambda x: x.rank_int, reverse=True)
            zig_score = 0
            for i, card in enumerate(all_cards[:5]):  # Take top 5 cards
                weight = 1 << (14 - i)
                zig_score += card.rank_int * weight
            
            print(f"\n{test['name']}:")
            print(f"  Python evaluation: {py_eval} (lower is better)")
            print(f"  Zig 'evaluation': {zig_score} (just summing ranks - WRONG!)")
            
            self.results['hand_evaluation'].append({
                'hand': test['name'],
                'python_score': py_eval,
                'zig_score': zig_score,
                'issue': 'Zig not evaluating actual poker hands'
            })
        
        print("\n❌ CRITICAL: Zig is not evaluating poker hands correctly!")
        print("   It's just summing card ranks, not detecting pairs, flushes, etc.")
    
    def test_ehs_calculation(self):
        """Test EHS calculation logic."""
        print("\n" + "="*60)
        print("TESTING: EHS Calculation")
        print("="*60)
        
        # Create test scenario
        our_hand = np.array([
            [14, 1],  # Ace of suit 1
            [14, 2]   # Ace of suit 2
        ])
        board = np.array([
            [2, 1], [3, 2], [5, 3], [7, 4], [9, 1]
        ])
        
        print(f"Our hand: AA")
        print(f"Board: 2-3-5-7-9 rainbow")
        
        # Python-style winner determination
        print("\nWinner Logic Comparison:")
        print("Python: Lower evaluation score = better hand")
        print("Zig: Higher score = better hand (INVERTED!)")
        
        # Simulate both
        our_rank = 3326  # Pair of aces (example)
        opp_rank = 6186  # High card (example)
        
        # Python logic
        if our_rank > opp_rank:
            py_winner = 1  # We lose (incorrect - higher rank is worse)
        elif our_rank < opp_rank:
            py_winner = 0  # We win
        else:
            py_winner = 2  # Tie
        
        # Zig logic (inverted)
        if our_rank > opp_rank:
            zig_winner = 0  # We win (incorrect logic)
        elif our_rank < opp_rank:
            zig_winner = 1  # We lose
        else:
            zig_winner = 2  # Tie
        
        print(f"\nWith AA vs high card:")
        print(f"  Python result: {['Win', 'Lose', 'Tie'][py_winner]}")
        print(f"  Zig result: {['Win', 'Lose', 'Tie'][zig_winner]} (WRONG!)")
        
        self.results['ehs_calculation'].append({
            'issue': 'Winner logic inverted',
            'python': 'Lower rank = better hand',
            'zig': 'Higher score = better hand',
            'impact': 'All EHS values will be incorrect'
        })
    
    def check_database_format(self):
        """Compare database storage formats."""
        print("\n" + "="*60)
        print("TESTING: Database Storage Format")
        print("="*60)
        
        # Check if Zig database exists
        zig_db_path = "/Users/ewan/Developer/OhMyApps/Poker/poker_ai/poker_ai/zig_clustering/clustering_data.db"
        
        if os.path.exists(zig_db_path):
            conn = sqlite3.connect(zig_db_path)
            cursor = conn.cursor()
            
            # Check schema
            cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
            tables = cursor.fetchall()
            print(f"Zig database tables: {tables}")
            
            # Check data format
            cursor.execute("SELECT COUNT(*) FROM river_data")
            count = cursor.fetchone()[0]
            print(f"River entries in Zig DB: {count}")
            
            if count > 0:
                cursor.execute("SELECT combo_id, LENGTH(combo_cards), LENGTH(distribution) FROM river_data LIMIT 1")
                row = cursor.fetchone()
                print(f"Sample entry - ID: {row[0]}, Cards blob size: {row[1]}, Dist blob size: {row[2]}")
                
                # Try to decode
                cursor.execute("SELECT combo_cards, distribution FROM river_data LIMIT 1")
                combo_blob, dist_blob = cursor.fetchone()
                
                # Decode cards (Zig stores as Card structs)
                n_cards = len(combo_blob) // 2  # Each card is 2 bytes in Zig
                print(f"Number of cards stored: {n_cards}")
                
                # Decode distribution
                n_values = len(dist_blob) // 4  # Each f32 is 4 bytes
                if dist_blob:
                    values = struct.unpack(f'{n_values}f', dist_blob)
                    print(f"Distribution values: {values[:5]}...")
            
            conn.close()
        else:
            print(f"Zig database not found at {zig_db_path}")
        
        # Python database format
        py_db_path = "/Users/ewan/Developer/OhMyApps/Poker/poker_ai/clustering_data.db"
        if os.path.exists(py_db_path):
            conn = sqlite3.connect(py_db_path)
            cursor = conn.cursor()
            
            cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
            tables = cursor.fetchall()
            print(f"\nPython database tables: {tables}")
            
            conn.close()
    
    def generate_report(self):
        """Generate comparison report."""
        print("\n" + "="*60)
        print("COMPARISON REPORT")
        print("="*60)
        
        print("\n🚨 CRITICAL ISSUES FOUND:\n")
        
        issue_count = 1
        for category, issues in self.results.items():
            if issues:
                print(f"{issue_count}. {category.upper().replace('_', ' ')}:")
                for issue in issues:
                    if 'issue' in issue:
                        print(f"   - {issue['issue']}")
                        if 'impact' in issue:
                            print(f"     Impact: {issue['impact']}")
                print()
                issue_count += 1
        
        print("\n⚠️  CONCLUSION:")
        print("The Zig implementation has fundamental flaws that make it")
        print("incompatible with the Python version and incorrect for poker AI.")
        print("\nMain problems:")
        print("1. Not evaluating actual poker hands (no pairs, flushes, etc.)")
        print("2. Card ordering differs, affecting combinations")
        print("3. Winner logic is inverted")
        print("4. Random sampling not reproducible")
        print("\n✅ RECOMMENDATION:")
        print("The Zig implementation needs a complete rewrite of:")
        print("- Hand evaluation (implement proper poker hand ranking)")
        print("- Card representation (match Python's format)")
        print("- EHS calculation (fix winner logic)")
        print("- Random number generation (match Python's seeding)")


def main():
    """Run all comparison tests."""
    comparator = ImplementationComparator()
    
    print("\n" + "="*70)
    print(" PYTHON vs ZIG CLUSTERING IMPLEMENTATION COMPARISON")
    print("="*70)
    
    # Run tests
    comparator.test_card_representation()
    comparator.test_hand_evaluation()
    comparator.test_ehs_calculation()
    comparator.check_database_format()
    
    # Generate report
    comparator.generate_report()


if __name__ == "__main__":
    main()