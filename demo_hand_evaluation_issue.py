#!/usr/bin/env python3
"""
Demonstrate the critical hand evaluation issue in Zig implementation.
"""

import sys
sys.path.insert(0, '/Users/ewan/Developer/OhMyApps/Poker/poker_ai')

from poker_ai.poker.card import Card
from poker_ai.poker.evaluation import Evaluator


def simulate_zig_evaluation(cards):
    """Simulate what Zig is doing (WRONG!)"""
    # Sort by rank descending
    cards_sorted = sorted(cards, key=lambda c: c.rank_int, reverse=True)
    
    score = 0
    for i, card in enumerate(cards_sorted[:5]):
        weight = 1 << (14 - i)
        score += card.rank_int * weight
    return score


def main():
    evaluator = Evaluator()
    
    print("="*70)
    print("CRITICAL BUG: Zig doesn't detect poker hands!")
    print("="*70)
    
    test_cases = [
        {
            'name': 'FLUSH beats PAIR',
            'hand1': {
                'cards': [Card(2, "hearts"), Card(5, "hearts")],
                'board': [Card(7, "hearts"), Card(9, "hearts"), Card(10, "hearts"),
                         Card(3, "diamonds"), Card(4, "clubs")],
                'description': 'Flush (all hearts)'
            },
            'hand2': {
                'cards': [Card(14, "spades"), Card(14, "diamonds")],
                'board': [Card(7, "hearts"), Card(9, "hearts"), Card(10, "hearts"),
                         Card(3, "diamonds"), Card(4, "clubs")],
                'description': 'Pair of Aces'
            }
        },
        {
            'name': 'STRAIGHT beats TWO PAIR',
            'hand1': {
                'cards': [Card(6, "spades"), Card(8, "diamonds")],
                'board': [Card(5, "hearts"), Card(7, "clubs"), Card(9, "diamonds"),
                         Card(2, "hearts"), Card(3, "clubs")],
                'description': 'Straight (5-6-7-8-9)'
            },
            'hand2': {
                'cards': [Card(14, "spades"), Card(14, "diamonds")],
                'board': [Card(13, "hearts"), Card(13, "clubs"), Card(2, "diamonds"),
                         Card(3, "hearts"), Card(4, "clubs")],
                'description': 'Two Pair (AA + KK)'
            }
        },
        {
            'name': 'THREE OF A KIND beats TWO PAIR',
            'hand1': {
                'cards': [Card(5, "spades"), Card(5, "diamonds")],
                'board': [Card(5, "hearts"), Card(2, "clubs"), Card(3, "diamonds"),
                         Card(7, "hearts"), Card(9, "clubs")],
                'description': 'Three 5s'
            },
            'hand2': {
                'cards': [Card(14, "spades"), Card(14, "diamonds")],
                'board': [Card(13, "hearts"), Card(13, "clubs"), Card(2, "diamonds"),
                         Card(3, "hearts"), Card(4, "clubs")],
                'description': 'Two Pair (AA + KK)'
            }
        }
    ]
    
    for test in test_cases:
        print(f"\n{test['name']}")
        print("-"*50)
        
        # Hand 1
        all_cards1 = test['hand1']['cards'] + test['hand1']['board']
        py_eval1 = evaluator.evaluate(
            board=[int(c) for c in test['hand1']['board']],
            cards=[int(c) for c in test['hand1']['cards']]
        )
        zig_eval1 = simulate_zig_evaluation(all_cards1)
        
        # Hand 2
        all_cards2 = test['hand2']['cards'] + test['hand2']['board']
        py_eval2 = evaluator.evaluate(
            board=[int(c) for c in test['hand2']['board']],
            cards=[int(c) for c in test['hand2']['cards']]
        )
        zig_eval2 = simulate_zig_evaluation(all_cards2)
        
        print(f"\n{test['hand1']['description']}:")
        print(f"  Python eval: {py_eval1} (lower is better)")
        print(f"  Zig 'eval':  {zig_eval1}")
        
        print(f"\n{test['hand2']['description']}:")
        print(f"  Python eval: {py_eval2} (lower is better)")
        print(f"  Zig 'eval':  {zig_eval2}")
        
        # Determine winners
        py_winner = "Hand 1" if py_eval1 < py_eval2 else "Hand 2"
        zig_winner = "Hand 1" if zig_eval1 > zig_eval2 else "Hand 2"
        
        print(f"\n✅ Python (CORRECT): {py_winner} wins")
        print(f"❌ Zig (WRONG):      {zig_winner} wins")
        
        if py_winner != zig_winner:
            print(f"⚠️  ZIG GETS IT COMPLETELY WRONG!")
    
    print("\n" + "="*70)
    print("CONCLUSION:")
    print("Zig implementation doesn't understand poker at all!")
    print("It can't detect flushes, straights, or even pairs properly.")
    print("ALL clustering data from Zig is INVALID.")
    print("="*70)


if __name__ == "__main__":
    main()