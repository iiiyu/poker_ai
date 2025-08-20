"""
Golden dataset generator and validator for Zig-Python compatibility.

This module generates and manages golden reference datasets from the Python
implementation that serve as the ground truth for validating Zig implementations.
"""

import json
import pickle
import hashlib
import time
from pathlib import Path
from typing import List, Dict, Any, Optional
import sys

from .base_validator import BaseValidator
from .test_data_generator import TestDataGenerator

# Add project root to path
sys.path.append(str(Path(__file__).parent.parent))

try:
    from poker_ai.poker.evaluation.evaluator import Evaluator
    from poker_ai.poker.evaluation.eval_card import EvaluationCard
    PYTHON_AVAILABLE = True
except ImportError as e:
    PYTHON_AVAILABLE = False


class GoldenDataset:
    """Golden reference dataset for validation."""
    
    def __init__(self, name: str, description: str, version: str = "1.0"):
        self.name = name
        self.description = description
        self.version = version
        self.created_at = time.time()
        self.data = []
        self.metadata = {}
        self.checksum = None
    
    def add_sample(self, input_data: Any, expected_output: Any, metadata: Dict = None):
        """Add a sample to the golden dataset."""
        sample = {
            "id": len(self.data),
            "input": input_data,
            "expected_output": expected_output,
            "metadata": metadata or {},
            "timestamp": time.time()
        }
        self.data.append(sample)
    
    def finalize(self):
        """Finalize the dataset and compute checksum."""
        dataset_content = json.dumps(self.data, sort_keys=True, default=str)
        self.checksum = hashlib.sha256(dataset_content.encode()).hexdigest()
        
        self.metadata.update({
            "sample_count": len(self.data),
            "finalized_at": time.time(),
            "checksum": self.checksum
        })
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert dataset to dictionary for serialization."""
        return {
            "name": self.name,
            "description": self.description,
            "version": self.version,
            "created_at": self.created_at,
            "metadata": self.metadata,
            "data": self.data,
            "checksum": self.checksum
        }
    
    def verify_integrity(self) -> bool:
        """Verify dataset integrity using checksum."""
        if not self.checksum:
            return False
        
        dataset_content = json.dumps(self.data, sort_keys=True, default=str)
        computed_checksum = hashlib.sha256(dataset_content.encode()).hexdigest()
        
        return computed_checksum == self.checksum


class GoldenDatasetGenerator(BaseValidator):
    """Generate golden reference datasets from Python implementation."""
    
    def __init__(self, project_root: Path = None):
        super().__init__(project_root)
        
        if PYTHON_AVAILABLE:
            self.evaluator = Evaluator()
        else:
            self.evaluator = None
        
        self.datasets_dir = self.validation_dir / "golden_datasets"
        self.datasets_dir.mkdir(exist_ok=True)
        
        self.test_generator = TestDataGenerator(self.validation_dir / "data")
    
    def get_test_description(self) -> str:
        return "Generates golden reference datasets from Python implementation for Zig validation"
    
    def run_tests(self) -> bool:
        """Generate all golden datasets."""
        if not PYTHON_AVAILABLE:
            self.logger.error("Python poker_ai not available - cannot generate golden datasets")
            return False
        
        all_generated = True
        
        # Dataset generation methods
        generation_methods = [
            self.generate_hand_evaluation_golden_dataset,
            self.generate_clustering_golden_dataset,
            self.generate_edge_cases_golden_dataset,
            self.generate_performance_golden_dataset,
            self.generate_regression_golden_dataset,
        ]
        
        for generation_method in generation_methods:
            try:
                self.logger.info(f"Running {generation_method.__name__}...")
                result = generation_method()
                if not result:
                    all_generated = False
            except Exception as e:
                self.logger.error(f"Dataset generation {generation_method.__name__} failed: {e}")
                all_generated = False
        
        return all_generated
    
    def generate_hand_evaluation_golden_dataset(self) -> bool:
        """Generate golden dataset for hand evaluation."""
        self.logger.info("Generating hand evaluation golden dataset...")
        
        try:
            dataset = GoldenDataset(
                name="hand_evaluation_golden",
                description="Golden reference dataset for hand evaluation validation",
                version="1.0"
            )
            
            # Generate comprehensive hand evaluation samples
            test_cases = [
                # Royal flushes
                (["As", "Ks", "Qs", "Js", "Ts", "2h", "3d"], "royal_flush_spades"),
                (["Ah", "Kh", "Qh", "Jh", "Th", "2s", "3d"], "royal_flush_hearts"),
                
                # Straight flushes
                (["9s", "8s", "7s", "6s", "5s", "2h", "3d"], "straight_flush_9_high"),
                (["As", "2s", "3s", "4s", "5s", "Kh", "Qd"], "wheel_straight_flush"),
                
                # Four of a kind
                (["As", "Ah", "Ad", "Ac", "Ks", "2h", "3d"], "four_aces"),
                (["2s", "2h", "2d", "2c", "As", "Kh", "Qd"], "four_twos"),
                
                # Full houses
                (["As", "Ah", "Ad", "Ks", "Kh", "2s", "3d"], "aces_full_of_kings"),
                (["Ks", "Kh", "Kd", "As", "Ah", "2s", "3d"], "kings_full_of_aces"),
                
                # Flushes
                (["As", "Qs", "Ts", "8s", "6s", "2h", "3d"], "ace_high_flush_spades"),
                (["Kh", "Qh", "Jh", "9h", "7h", "As", "2d"], "king_high_flush_hearts"),
                
                # Straights
                (["As", "Kh", "Qd", "Jc", "Ts", "2h", "3d"], "broadway_straight"),
                (["As", "2h", "3d", "4c", "5s", "Kh", "Qd"], "wheel_straight"),
                (["9s", "8h", "7d", "6c", "5s", "As", "Kd"], "nine_high_straight"),
                
                # Three of a kind
                (["As", "Ah", "Ad", "Ks", "Qh", "Js", "Td"], "trip_aces"),
                (["2s", "2h", "2d", "As", "Kh", "Qs", "Jd"], "trip_twos"),
                
                # Two pair
                (["As", "Ah", "Ks", "Kh", "Qd", "Js", "Td"], "aces_and_kings"),
                (["Qs", "Qh", "Js", "Jh", "Ad", "Ks", "Td"], "queens_and_jacks"),
                
                # One pair
                (["As", "Ah", "Ks", "Qh", "Jd", "Ts", "9d"], "pair_of_aces"),
                (["2s", "2h", "As", "Kh", "Qd", "Js", "Td"], "pair_of_twos"),
                
                # High card
                (["As", "Kh", "Qd", "Jc", "9s", "7h", "5d"], "ace_high"),
                (["Ks", "Qh", "Jd", "Tc", "8s", "6h", "4d"], "king_high"),
            ]
            
            # Add systematic test cases
            for cards, description in test_cases:
                try:
                    # Evaluate with Python
                    eval_cards = [EvaluationCard.new(card) for card in cards]
                    rank = self.evaluator.evaluate(eval_cards[:5], eval_cards[5:])
                    hand_class = self.evaluator.get_rank_class(rank)
                    hand_class_name = self.evaluator.class_to_string(hand_class)
                    
                    dataset.add_sample(
                        input_data={"cards": cards},
                        expected_output={
                            "rank": rank,
                            "hand_class": hand_class,
                            "hand_class_name": hand_class_name
                        },
                        metadata={
                            "description": description,
                            "test_type": "systematic"
                        }
                    )
                    
                except Exception as e:
                    self.logger.warning(f"Failed to evaluate {cards}: {e}")
                    continue
            
            # Add random samples
            self.logger.info("Adding random hand evaluation samples...")
            
            import random
            ranks = '23456789TJQKA'
            suits = 'shdc'
            deck = [f"{rank}{suit}" for rank in ranks for suit in suits]
            
            for i in range(1000):  # 1000 random samples
                try:
                    # Generate random 7-card hand
                    random_hand = random.sample(deck, 7)
                    
                    # Evaluate with Python
                    eval_cards = [EvaluationCard.new(card) for card in random_hand]
                    rank = self.evaluator.evaluate(eval_cards[:5], eval_cards[5:])
                    hand_class = self.evaluator.get_rank_class(rank)
                    hand_class_name = self.evaluator.class_to_string(hand_class)
                    
                    dataset.add_sample(
                        input_data={"cards": random_hand},
                        expected_output={
                            "rank": rank,
                            "hand_class": hand_class,
                            "hand_class_name": hand_class_name
                        },
                        metadata={
                            "description": f"random_sample_{i}",
                            "test_type": "random"
                        }
                    )
                    
                except Exception as e:
                    continue
            
            # Finalize and save dataset
            dataset.finalize()
            
            output_file = self.datasets_dir / "hand_evaluation_golden.json"
            with open(output_file, 'w') as f:
                json.dump(dataset.to_dict(), f, indent=2, default=str)
            
            self.logger.info(f"Hand evaluation golden dataset saved: {output_file}")
            self.logger.info(f"Generated {len(dataset.data)} samples")
            
            self.create_result(
                test_name="generate_hand_evaluation_golden_dataset",
                passed=True,
                message=f"Generated {len(dataset.data)} samples",
                python_result={
                    "dataset_file": str(output_file),
                    "sample_count": len(dataset.data),
                    "checksum": dataset.checksum
                },
                zig_result=None
            )
            
            return True
            
        except Exception as e:
            self.logger.error(f"Hand evaluation golden dataset generation failed: {e}")
            self.create_result(
                test_name="generate_hand_evaluation_golden_dataset",
                passed=False,
                message=f"Exception: {e}",
                python_result=None,
                zig_result=None
            )
            return False
    
    def generate_clustering_golden_dataset(self) -> bool:
        """Generate golden dataset for clustering validation."""
        self.logger.info("Generating clustering golden dataset...")
        
        try:
            dataset = GoldenDataset(
                name="clustering_golden",
                description="Golden reference dataset for clustering validation",
                version="1.0"
            )
            
            # Generate clustering test cases
            import random
            ranks = '23456789TJQKA'
            suits = 'shdc'
            deck = [f"{rank}{suit}" for rank in ranks for suit in suits]
            
            for i in range(500):  # 500 clustering samples
                try:
                    # Generate hand sequence (preflop -> river)
                    random.shuffle(deck)
                    
                    hole_cards = deck[:2]
                    flop = deck[2:5]
                    turn = deck[5:6]
                    river = deck[6:7]
                    
                    # Create stage hands
                    preflop_hand = hole_cards
                    flop_hand = hole_cards + flop
                    turn_hand = hole_cards + flop + turn
                    river_hand = hole_cards + flop + turn + river
                    
                    # Evaluate final hand
                    eval_cards = [EvaluationCard.new(card) for card in river_hand]
                    final_rank = self.evaluator.evaluate(eval_cards[:5], eval_cards[5:] if len(eval_cards) > 5 else [])
                    final_class = self.evaluator.get_rank_class(final_rank)
                    
                    # Calculate hand strength at each stage (simplified)
                    hand_strengths = {}
                    for stage_name, stage_cards in [
                        ("preflop", preflop_hand),
                        ("flop", flop_hand),
                        ("turn", turn_hand),
                        ("river", river_hand)
                    ]:
                        if len(stage_cards) >= 5:
                            stage_eval_cards = [EvaluationCard.new(card) for card in stage_cards]
                            stage_rank = self.evaluator.evaluate(stage_eval_cards[:5], stage_eval_cards[5:])
                            hand_strengths[stage_name] = {
                                "rank": stage_rank,
                                "strength": 7462 - stage_rank  # Convert to strength (higher = better)
                            }
                        else:
                            # For preflop/early stages, use placeholder
                            hand_strengths[stage_name] = {
                                "rank": None,
                                "strength": 0  # Placeholder
                            }
                    
                    dataset.add_sample(
                        input_data={
                            "hole_cards": hole_cards,
                            "flop": flop,
                            "turn": turn,
                            "river": river,
                            "stages": {
                                "preflop": preflop_hand,
                                "flop": flop_hand,
                                "turn": turn_hand,
                                "river": river_hand
                            }
                        },
                        expected_output={
                            "final_rank": final_rank,
                            "final_class": final_class,
                            "hand_strengths": hand_strengths
                        },
                        metadata={
                            "description": f"clustering_sample_{i}",
                            "test_type": "clustering"
                        }
                    )
                    
                except Exception as e:
                    continue
            
            # Finalize and save dataset
            dataset.finalize()
            
            output_file = self.datasets_dir / "clustering_golden.json"
            with open(output_file, 'w') as f:
                json.dump(dataset.to_dict(), f, indent=2, default=str)
            
            self.logger.info(f"Clustering golden dataset saved: {output_file}")
            self.logger.info(f"Generated {len(dataset.data)} samples")
            
            self.create_result(
                test_name="generate_clustering_golden_dataset",
                passed=True,
                message=f"Generated {len(dataset.data)} samples",
                python_result={
                    "dataset_file": str(output_file),
                    "sample_count": len(dataset.data),
                    "checksum": dataset.checksum
                },
                zig_result=None
            )
            
            return True
            
        except Exception as e:
            self.logger.error(f"Clustering golden dataset generation failed: {e}")
            self.create_result(
                test_name="generate_clustering_golden_dataset",
                passed=False,
                message=f"Exception: {e}",
                python_result=None,
                zig_result=None
            )
            return False
    
    def generate_edge_cases_golden_dataset(self) -> bool:
        """Generate golden dataset for edge cases."""
        self.logger.info("Generating edge cases golden dataset...")
        
        try:
            dataset = GoldenDataset(
                name="edge_cases_golden",
                description="Golden reference dataset for edge case validation",
                version="1.0"
            )
            
            # Edge case test scenarios
            edge_cases = [
                # Tie scenarios
                (["As", "Ks", "Qs", "Js", "Ts", "2h", "3d"], 
                 ["Ah", "Kh", "Qh", "Jh", "Th", "2s", "3c"], "royal_flush_tie"),
                
                # Kicker comparisons
                (["As", "Ah", "Ks", "Qh", "Jd", "Ts", "9d"],
                 ["As", "Ad", "Ks", "Qh", "Jd", "Ts", "8d"], "pair_aces_kicker_9_vs_8"),
                
                # Wheel straight vs higher straight
                (["As", "2h", "3d", "4c", "5s", "Kh", "Qd"],
                 ["9s", "8h", "7d", "6c", "5s", "4h", "3d"], "wheel_vs_nine_high_straight"),
                
                # Low ace in straight
                (["As", "2h", "3d", "4c", "5s", "6h", "7d"], "ace_low_straight_with_extras"),
                
                # High card tie-breaking
                (["As", "Kh", "Qd", "Jc", "9s", "7h", "5d"],
                 ["As", "Kh", "Qd", "Jc", "9s", "7h", "4d"], "high_card_tie_kicker"),
            ]
            
            for i, edge_case in enumerate(edge_cases):
                if len(edge_case) == 3:
                    # Comparison case
                    hand1, hand2, description = edge_case
                    
                    try:
                        # Evaluate both hands
                        eval_cards1 = [EvaluationCard.new(card) for card in hand1]
                        eval_cards2 = [EvaluationCard.new(card) for card in hand2]
                        
                        rank1 = self.evaluator.evaluate(eval_cards1[:5], eval_cards1[5:])
                        rank2 = self.evaluator.evaluate(eval_cards2[:5], eval_cards2[5:])
                        
                        comparison = "tie" if rank1 == rank2 else ("hand1_wins" if rank1 < rank2 else "hand2_wins")
                        
                        dataset.add_sample(
                            input_data={
                                "hand1": hand1,
                                "hand2": hand2,
                                "comparison_type": "edge_case"
                            },
                            expected_output={
                                "rank1": rank1,
                                "rank2": rank2,
                                "comparison": comparison
                            },
                            metadata={
                                "description": description,
                                "test_type": "edge_case_comparison"
                            }
                        )
                        
                    except Exception as e:
                        self.logger.warning(f"Failed to evaluate edge case {description}: {e}")
                        continue
                else:
                    # Single hand edge case
                    hand, description = edge_case[:2]
                    
                    try:
                        eval_cards = [EvaluationCard.new(card) for card in hand]
                        rank = self.evaluator.evaluate(eval_cards[:5], eval_cards[5:])
                        hand_class = self.evaluator.get_rank_class(rank)
                        hand_class_name = self.evaluator.class_to_string(hand_class)
                        
                        dataset.add_sample(
                            input_data={"cards": hand},
                            expected_output={
                                "rank": rank,
                                "hand_class": hand_class,
                                "hand_class_name": hand_class_name
                            },
                            metadata={
                                "description": description,
                                "test_type": "edge_case_single"
                            }
                        )
                        
                    except Exception as e:
                        self.logger.warning(f"Failed to evaluate edge case {description}: {e}")
                        continue
            
            # Add boundary value testing
            boundary_cases = [
                # Lowest possible hands
                (["2s", "3h", "4d", "5c", "7s", "8h", "9d"], "lowest_high_card"),
                (["2s", "2h", "3d", "4c", "5s", "6h", "7d"], "lowest_pair"),
                
                # Highest possible hands
                (["As", "Ks", "Qs", "Js", "Ts", "2h", "3d"], "royal_flush_spades"),
                (["As", "Ah", "Ad", "Ac", "Ks", "2h", "3d"], "four_aces"),
            ]
            
            for hand, description in boundary_cases:
                try:
                    eval_cards = [EvaluationCard.new(card) for card in hand]
                    rank = self.evaluator.evaluate(eval_cards[:5], eval_cards[5:])
                    hand_class = self.evaluator.get_rank_class(rank)
                    hand_class_name = self.evaluator.class_to_string(hand_class)
                    
                    dataset.add_sample(
                        input_data={"cards": hand},
                        expected_output={
                            "rank": rank,
                            "hand_class": hand_class,
                            "hand_class_name": hand_class_name
                        },
                        metadata={
                            "description": description,
                            "test_type": "boundary_case"
                        }
                    )
                    
                except Exception as e:
                    continue
            
            # Finalize and save dataset
            dataset.finalize()
            
            output_file = self.datasets_dir / "edge_cases_golden.json"
            with open(output_file, 'w') as f:
                json.dump(dataset.to_dict(), f, indent=2, default=str)
            
            self.logger.info(f"Edge cases golden dataset saved: {output_file}")
            self.logger.info(f"Generated {len(dataset.data)} samples")
            
            self.create_result(
                test_name="generate_edge_cases_golden_dataset",
                passed=True,
                message=f"Generated {len(dataset.data)} samples",
                python_result={
                    "dataset_file": str(output_file),
                    "sample_count": len(dataset.data),
                    "checksum": dataset.checksum
                },
                zig_result=None
            )
            
            return True
            
        except Exception as e:
            self.logger.error(f"Edge cases golden dataset generation failed: {e}")
            self.create_result(
                test_name="generate_edge_cases_golden_dataset",
                passed=False,
                message=f"Exception: {e}",
                python_result=None,
                zig_result=None
            )
            return False
    
    def generate_performance_golden_dataset(self) -> bool:
        """Generate golden dataset for performance benchmarking."""
        self.logger.info("Generating performance golden dataset...")
        
        try:
            dataset = GoldenDataset(
                name="performance_golden",
                description="Golden reference dataset for performance benchmarking",
                version="1.0"
            )
            
            # Generate performance test samples
            import random
            ranks = '23456789TJQKA'
            suits = 'shdc'
            deck = [f"{rank}{suit}" for rank in ranks for suit in suits]
            
            # Large dataset for performance testing
            for batch in range(10):  # 10 batches
                batch_samples = []
                
                for i in range(1000):  # 1000 samples per batch
                    try:
                        # Generate random 7-card hand
                        random_hand = random.sample(deck, 7)
                        
                        # Evaluate with Python (including timing)
                        start_time = time.perf_counter()
                        eval_cards = [EvaluationCard.new(card) for card in random_hand]
                        rank = self.evaluator.evaluate(eval_cards[:5], eval_cards[5:])
                        end_time = time.perf_counter()
                        
                        evaluation_time = end_time - start_time
                        hand_class = self.evaluator.get_rank_class(rank)
                        
                        batch_samples.append({
                            "cards": random_hand,
                            "rank": rank,
                            "hand_class": hand_class,
                            "evaluation_time": evaluation_time
                        })
                        
                    except Exception as e:
                        continue
                
                # Add batch as single sample
                dataset.add_sample(
                    input_data={
                        "batch_id": batch,
                        "hands": [sample["cards"] for sample in batch_samples]
                    },
                    expected_output={
                        "batch_results": batch_samples,
                        "total_hands": len(batch_samples),
                        "avg_time": sum(s["evaluation_time"] for s in batch_samples) / len(batch_samples) if batch_samples else 0
                    },
                    metadata={
                        "description": f"performance_batch_{batch}",
                        "test_type": "performance",
                        "batch_size": len(batch_samples)
                    }
                )
            
            # Finalize and save dataset
            dataset.finalize()
            
            output_file = self.datasets_dir / "performance_golden.json"
            with open(output_file, 'w') as f:
                json.dump(dataset.to_dict(), f, indent=2, default=str)
            
            self.logger.info(f"Performance golden dataset saved: {output_file}")
            self.logger.info(f"Generated {len(dataset.data)} batches")
            
            self.create_result(
                test_name="generate_performance_golden_dataset",
                passed=True,
                message=f"Generated {len(dataset.data)} performance batches",
                python_result={
                    "dataset_file": str(output_file),
                    "batch_count": len(dataset.data),
                    "checksum": dataset.checksum
                },
                zig_result=None
            )
            
            return True
            
        except Exception as e:
            self.logger.error(f"Performance golden dataset generation failed: {e}")
            self.create_result(
                test_name="generate_performance_golden_dataset",
                passed=False,
                message=f"Exception: {e}",
                python_result=None,
                zig_result=None
            )
            return False
    
    def generate_regression_golden_dataset(self) -> bool:
        """Generate golden dataset for regression testing."""
        self.logger.info("Generating regression golden dataset...")
        
        try:
            dataset = GoldenDataset(
                name="regression_golden",
                description="Golden reference dataset for regression testing",
                version="1.0"
            )
            
            # Generate consistent test cases for regression detection
            import random
            
            # Use fixed seed for reproducible regression testing
            random.seed(42)
            
            ranks = '23456789TJQKA'
            suits = 'shdc'
            deck = [f"{rank}{suit}" for rank in ranks for suit in suits]
            
            for i in range(100):  # 100 regression test samples
                try:
                    # Generate deterministic hand based on index
                    random.seed(42 + i)  # Deterministic but varied
                    test_hand = random.sample(deck, 7)
                    
                    # Evaluate with Python
                    eval_cards = [EvaluationCard.new(card) for card in test_hand]
                    rank = self.evaluator.evaluate(eval_cards[:5], eval_cards[5:])
                    hand_class = self.evaluator.get_rank_class(rank)
                    hand_class_name = self.evaluator.class_to_string(hand_class)
                    
                    dataset.add_sample(
                        input_data={
                            "cards": test_hand,
                            "test_id": i,
                            "seed": 42 + i
                        },
                        expected_output={
                            "rank": rank,
                            "hand_class": hand_class,
                            "hand_class_name": hand_class_name
                        },
                        metadata={
                            "description": f"regression_test_{i}",
                            "test_type": "regression",
                            "deterministic": True
                        }
                    )
                    
                except Exception as e:
                    continue
            
            # Reset random seed
            random.seed()
            
            # Finalize and save dataset
            dataset.finalize()
            
            output_file = self.datasets_dir / "regression_golden.json"
            with open(output_file, 'w') as f:
                json.dump(dataset.to_dict(), f, indent=2, default=str)
            
            self.logger.info(f"Regression golden dataset saved: {output_file}")
            self.logger.info(f"Generated {len(dataset.data)} regression tests")
            
            self.create_result(
                test_name="generate_regression_golden_dataset",
                passed=True,
                message=f"Generated {len(dataset.data)} regression tests",
                python_result={
                    "dataset_file": str(output_file),
                    "test_count": len(dataset.data),
                    "checksum": dataset.checksum
                },
                zig_result=None
            )
            
            return True
            
        except Exception as e:
            self.logger.error(f"Regression golden dataset generation failed: {e}")
            self.create_result(
                test_name="generate_regression_golden_dataset",
                passed=False,
                message=f"Exception: {e}",
                python_result=None,
                zig_result=None
            )
            return False
    
    def validate_golden_dataset(self, dataset_file: Path) -> bool:
        """Validate integrity of a golden dataset."""
        try:
            with open(dataset_file, 'r') as f:
                dataset_dict = json.load(f)
            
            # Recreate dataset object
            dataset = GoldenDataset(
                name=dataset_dict["name"],
                description=dataset_dict["description"],
                version=dataset_dict["version"]
            )
            
            dataset.created_at = dataset_dict["created_at"]
            dataset.metadata = dataset_dict["metadata"]
            dataset.data = dataset_dict["data"]
            dataset.checksum = dataset_dict["checksum"]
            
            # Verify integrity
            return dataset.verify_integrity()
            
        except Exception as e:
            self.logger.error(f"Failed to validate dataset {dataset_file}: {e}")
            return False
    
    def load_golden_dataset(self, dataset_name: str) -> Optional[GoldenDataset]:
        """Load a golden dataset by name."""
        dataset_file = self.datasets_dir / f"{dataset_name}.json"
        
        if not dataset_file.exists():
            self.logger.error(f"Golden dataset not found: {dataset_file}")
            return None
        
        try:
            with open(dataset_file, 'r') as f:
                dataset_dict = json.load(f)
            
            # Recreate dataset object
            dataset = GoldenDataset(
                name=dataset_dict["name"],
                description=dataset_dict["description"],
                version=dataset_dict["version"]
            )
            
            dataset.created_at = dataset_dict["created_at"]
            dataset.metadata = dataset_dict["metadata"]
            dataset.data = dataset_dict["data"]
            dataset.checksum = dataset_dict["checksum"]
            
            # Verify integrity
            if not dataset.verify_integrity():
                self.logger.error(f"Dataset integrity check failed: {dataset_name}")
                return None
            
            return dataset
            
        except Exception as e:
            self.logger.error(f"Failed to load golden dataset {dataset_name}: {e}")
            return None


def main():
    """Generate all golden datasets."""
    generator = GoldenDatasetGenerator()
    success = generator.run_and_report()
    
    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())