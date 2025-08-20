#!/usr/bin/env python3
"""
Validation script to compare Zig hand evaluator against Python implementation.
This script generates test cases and validates that both implementations
produce identical results.
"""

import sys
import json
from pathlib import Path
from typing import List, Tuple, Dict, Any

# Add poker_ai to path
poker_ai_path = Path(__file__).parent / "poker_ai"
sys.path.insert(0, str(poker_ai_path))

from poker_ai.poker.evaluation import Evaluator, EvaluationCard

class HandEvaluatorValidator:
    """Validates Zig implementation against Python implementation."""
    
    def __init__(self):
        self.python_evaluator = Evaluator()
        self.test_cases = []
    
    def generate_test_cases(self) -> List[Dict[str, Any]]:
        """Generate comprehensive test cases for validation."""
        test_cases = []
        
        # 1. Known hand rankings (from strongest to weakest)
        known_hands = [
            {
                "cards": ["As", "Ks", "Qs", "Js", "Ts"],
                "description": "Royal flush in spades",
                "expected_type": "Straight Flush",
            },
            {
                "cards": ["9s", "8s", "7s", "6s", "5s"],
                "description": "Nine-high straight flush",
                "expected_type": "Straight Flush",
            },
            {
                "cards": ["5s", "4s", "3s", "2s", "As"],
                "description": "Wheel straight flush (5-high)",
                "expected_type": "Straight Flush",
            },
            {
                "cards": ["As", "Ah", "Ad", "Ac", "Ks"],
                "description": "Four aces with king kicker",
                "expected_type": "Four of a Kind",
            },
            {
                "cards": ["2s", "2h", "2d", "2c", "3s"],
                "description": "Four deuces with three kicker",
                "expected_type": "Four of a Kind",
            },
            {
                "cards": ["As", "Ah", "Ad", "Ks", "Kh"],
                "description": "Aces full of kings",
                "expected_type": "Full House",
            },
            {
                "cards": ["2s", "2h", "2d", "3s", "3h"],
                "description": "Deuces full of threes",
                "expected_type": "Full House",
            },
            {
                "cards": ["As", "Js", "9s", "7s", "2s"],
                "description": "Ace-high flush in spades",
                "expected_type": "Flush",
            },
            {
                "cards": ["2h", "4h", "6h", "8h", "Th"],
                "description": "Ten-high flush in hearts",
                "expected_type": "Flush",
            },
            {
                "cards": ["As", "Kh", "Qd", "Jc", "Ts"],
                "description": "Broadway straight (mixed suits)",
                "expected_type": "Straight",
            },
            {
                "cards": ["5h", "4d", "3c", "2s", "Ah"],
                "description": "Wheel straight (mixed suits)",
                "expected_type": "Straight",
            },
            {
                "cards": ["As", "Ah", "Ad", "Ks", "Qs"],
                "description": "Trip aces with K-Q kickers",
                "expected_type": "Three of a Kind",
            },
            {
                "cards": ["2s", "2h", "2d", "3s", "4h"],
                "description": "Trip deuces with 4-3 kickers",
                "expected_type": "Three of a Kind",
            },
            {
                "cards": ["As", "Ah", "Ks", "Kh", "Qs"],
                "description": "Aces and kings with queen kicker",
                "expected_type": "Two Pair",
            },
            {
                "cards": ["2s", "2h", "3s", "3h", "4d"],
                "description": "Deuces and threes with four kicker",
                "expected_type": "Two Pair",
            },
            {
                "cards": ["As", "Ah", "Ks", "Qd", "Js"],
                "description": "Pair of aces with K-Q-J kickers",
                "expected_type": "Pair",
            },
            {
                "cards": ["2s", "2h", "3d", "4c", "5s"],
                "description": "Pair of deuces with 5-4-3 kickers",
                "expected_type": "Pair",
            },
            {
                "cards": ["As", "Kh", "Qd", "Jc", "9s"],
                "description": "Ace-high (A-K-Q-J-9)",
                "expected_type": "High Card",
            },
            {
                "cards": ["7s", "5h", "4d", "3c", "2s"],
                "description": "Seven-high (7-5-4-3-2)",
                "expected_type": "High Card",
            },
        ]
        
        # Evaluate each hand with Python implementation
        for hand_data in known_hands:
            cards_str = hand_data["cards"]
            cards_int = EvaluationCard.hand_to_binary(cards_str)
            
            # Evaluate the hand
            rank = self.python_evaluator.evaluate(cards_int[:2], cards_int[2:])
            rank_class = self.python_evaluator.get_rank_class(rank)
            class_string = self.python_evaluator.class_to_string(rank_class)
            
            test_case = {
                "cards": cards_str,
                "python_rank": rank,
                "python_type": class_string,
                "description": hand_data["description"],
                "expected_type": hand_data["expected_type"],
            }
            test_cases.append(test_case)
        
        return test_cases
    
    def save_test_cases(self, filename: str = "zig_validation_cases.json"):
        """Save test cases to JSON file for Zig to consume."""
        self.test_cases = self.generate_test_cases()
        
        output_file = Path(__file__).parent / "zig" / filename
        with open(output_file, 'w') as f:
            json.dump(self.test_cases, f, indent=2)
        
        print(f"✅ Generated {len(self.test_cases)} test cases")
        print(f"📁 Saved to: {output_file}")
        
        # Print summary
        type_counts = {}
        for case in self.test_cases:
            hand_type = case["python_type"]
            type_counts[hand_type] = type_counts.get(hand_type, 0) + 1
        
        print("\n📊 Test Case Summary:")
        for hand_type, count in sorted(type_counts.items()):
            print(f"  {hand_type}: {count}")
    
    def validate_card_representation(self):
        """Validate that our card bit representation matches Python."""
        print("\n🔍 Validating Card Representation:")
        print("=" * 40)
        
        test_cards = ["As", "Ks", "Qs", "Js", "Ts", "2c", "7h", "9d"]
        
        for card_str in test_cards:
            py_card = EvaluationCard.new(card_str)
            
            # Extract components
            rank_int = EvaluationCard.get_rank_int(py_card)
            suit_int = EvaluationCard.get_suit_int(py_card)
            bitrank = EvaluationCard.get_bitrank_int(py_card)
            prime = EvaluationCard.get_prime(py_card)
            
            print(f"Card: {card_str}")
            print(f"  Full value: 0x{py_card:08X} ({py_card})")
            print(f"  Rank: {rank_int} (0=2, 12=A)")
            print(f"  Suit: {suit_int} (1=♠, 2=♥, 4=♦, 8=♣)")
            print(f"  Bitrank: 0x{bitrank:04X}")
            print(f"  Prime: {prime}")
            print()
    
    def print_detailed_analysis(self):
        """Print detailed analysis of hand rankings."""
        print("\n📈 Detailed Hand Analysis:")
        print("=" * 50)
        
        for i, case in enumerate(self.test_cases):
            print(f"{i+1:2d}. {case['description']}")
            print(f"    Cards: {' '.join(case['cards'])}")
            print(f"    Rank: {case['python_rank']:4d} | Type: {case['python_type']}")
            
            # Verify type matches expectation
            if case['python_type'] == case['expected_type']:
                print(f"    ✅ Type matches expectation")
            else:
                print(f"    ❌ Expected: {case['expected_type']}, Got: {case['python_type']}")
            print()

def main():
    """Main validation routine."""
    print("🃏 Zig Hand Evaluator Validation Generator")
    print("=" * 45)
    
    validator = HandEvaluatorValidator()
    
    # Generate and save test cases
    validator.save_test_cases()
    
    # Validate card representation
    validator.validate_card_representation()
    
    # Print detailed analysis
    validator.print_detailed_analysis()
    
    print("\n✨ Validation data generated successfully!")
    print("\nNext steps:")
    print("1. cd zig")
    print("2. zig build test")
    print("3. Compare outputs to ensure identical results")

if __name__ == "__main__":
    main()