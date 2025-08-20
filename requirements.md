# zig_clustering_rewrite Requirements

## Introduction

Rewrite the poker_ai/clustering module in Zig to solve persistent memory limitation issues. The Python implementation, despite extensive refactoring including SQLite3 backing and streaming processing, still encounters memory pressure with billions of card combinations. This Zig implementation will leverage manual memory management, zero-cost abstractions, and optimized data structures to process clustering workloads efficiently within memory constraints while maintaining all existing algorithmic logic and SQLite3 interoperability.

## Requirements

### 1. Core Algorithm Implementation

**User Story**: As a poker AI developer, I want a memory-efficient clustering system that can process billions of card combinations, so that I can generate complete lookup tables (LUTs) without running out of memory.

**Acceptance Criteria**:
1.1. The system SHALL implement the exact same clustering algorithms as the Python version
1.2. The system SHALL process river, turn, and flop stages using K-means clustering with MiniBatch approach
1.3. The system SHALL calculate Expected Hand Strength (EHS) using Monte Carlo simulations
1.4. The system SHALL use Earth Mover's Distance (Wasserstein distance) for turn and flop potential-aware clustering
1.5. The system SHALL implement preflop lossless abstraction (169 starting hand combinations)
1.6. The system SHALL produce identical cluster assignments as the Python implementation for the same input parameters

### 2. Memory Management and Performance

**User Story**: As a system administrator, I want the clustering process to complete within available system memory limits, so that I can run it on resource-constrained servers.

**Acceptance Criteria**:
2.1. The system SHALL operate within configurable memory limits (e.g., 8GB, 16GB, 50GB)
2.2. The system SHALL use manual memory management to avoid garbage collection overhead
2.3. The system SHALL implement streaming processing to avoid loading all combinations into memory simultaneously
2.4. The system SHALL provide memory usage monitoring and reporting
2.5. The system SHALL implement emergency cleanup procedures when approaching memory limits
2.6. The system SHALL achieve at least 10x memory efficiency improvement over the Python implementation
2.7. The system SHALL complete full LUT generation at least 5x faster than the Python implementation

### 3. SQLite Integration and Data Persistence

**User Story**: As a poker AI developer, I want seamless integration with the existing SQLite database schema, so that I can maintain compatibility with the current system and enable incremental processing.

**Acceptance Criteria**:
3.1. The system SHALL read from and write to the existing SQLite3 database schema
3.2. The system SHALL support the same database tables: river_data, turn_data, flop_data, checkpoints
3.3. The system SHALL implement checkpoint/resume functionality for fault tolerance
3.4. The system SHALL compress distribution data using zlib before storing in database
3.5. The system SHALL support batch database operations for optimal I/O performance
3.6. The system SHALL maintain database integrity and ACID properties during processing
3.7. The system SHALL be compatible with existing Python tools that read the database

### 4. Card Representation and Combinations

**User Story**: As a poker AI developer, I want consistent card representation and combination generation, so that the Zig implementation produces the same results as the Python version.

**Acceptance Criteria**:
4.1. The system SHALL represent cards using the same integer encoding as the Python poker evaluation library
4.2. The system SHALL generate identical card combinations for starting hands, flop, turn, and river
4.3. The system SHALL implement the same card combination validation logic (no duplicate cards)
4.4. The system SHALL support configurable card rank ranges (e.g., 2-14 for full deck)
4.5. The system SHALL maintain sorted order of card combinations for deterministic processing
4.6. The system SHALL interface with the existing poker hand evaluation system

### 5. Clustering Configuration and Parameters

**User Story**: As a poker AI researcher, I want configurable clustering parameters, so that I can experiment with different cluster sizes and simulation counts.

**Acceptance Criteria**:
5.1. The system SHALL accept configurable number of clusters for river, turn, and flop stages
5.2. The system SHALL accept configurable number of Monte Carlo simulations for each stage
5.3. The system SHALL support configurable batch sizes for processing and database operations
5.4. The system SHALL accept configurable memory limits and safety factors
5.5. The system SHALL support configurable random seed for reproducible results
5.6. The system SHALL validate configuration parameters and provide meaningful error messages

### 6. Build System and Project Structure

**User Story**: As a developer, I want a clean project structure with a standard build system, so that I can easily build, test, and maintain the Zig implementation.

**Acceptance Criteria**:
6.1. The system SHALL use Zig's standard build system (build.zig)
6.2. The system SHALL organize code into logical modules: card representation, clustering algorithms, database interface, memory management
6.3. The system SHALL include comprehensive unit tests for all core functionality
6.4. The system SHALL include integration tests that compare output with Python implementation
6.5. The system SHALL provide clear documentation and usage examples
6.6. The system SHALL support multiple build modes: debug, release-safe, release-fast

### 7. Command Line Interface and Interoperability

**User Story**: As a poker AI developer, I want a command-line interface compatible with existing scripts, so that I can seamlessly replace the Python implementation in my workflow.

**Acceptance Criteria**:
7.1. The system SHALL provide a command-line interface with the same parameters as the Python version
7.2. The system SHALL output progress information and memory usage statistics
7.3. The system SHALL support verbose logging modes for debugging
7.4. The system SHALL produce identical output file formats (joblib-compatible LUT files)
7.5. The system SHALL return appropriate exit codes for success/failure scenarios
7.6. The system SHALL be callable from existing shell scripts without modification

### 8. Error Handling and Robustness

**User Story**: As a system operator, I want robust error handling and recovery, so that long-running clustering jobs don't fail unexpectedly.

**Acceptance Criteria**:
8.1. The system SHALL handle SQLite errors gracefully with appropriate retry logic
8.2. The system SHALL detect and recover from memory allocation failures
8.3. The system SHALL validate input data and provide clear error messages for invalid configurations
8.4. The system SHALL implement proper cleanup of resources on error conditions
8.5. The system SHALL support graceful shutdown on interrupt signals (SIGINT, SIGTERM)
8.6. The system SHALL log detailed error information for debugging
8.7. The system SHALL resume from the last valid checkpoint after failure

### 9. Algorithm Accuracy and Validation

**User Story**: As a poker AI researcher, I want mathematical accuracy identical to the Python implementation, so that I can trust the clustering results for training.

**Acceptance Criteria**:
9.1. The system SHALL produce EHS calculations with floating-point precision matching Python (within 1e-10)
9.2. The system SHALL implement Wasserstein distance calculation with identical results to scipy.stats
9.3. The system SHALL use the same random number generation approach for Monte Carlo simulations
9.4. The system SHALL implement K-means clustering with identical convergence criteria
9.5. The system SHALL validate cluster assignments against reference Python output
9.6. The system SHALL include regression tests to prevent algorithmic drift

### 10. Cross-Platform Compatibility

**User Story**: As a distributed computing user, I want the Zig implementation to run on multiple platforms, so that I can use it in different deployment environments.

**Acceptance Criteria**:
10.1. The system SHALL compile and run on Linux x86_64 systems
10.2. The system SHALL compile and run on macOS (Intel and Apple Silicon)
10.3. The system SHALL compile and run on Windows x86_64 systems
10.4. The system SHALL use SQLite3 libraries available on the target platform
10.5. The system SHALL handle platform-specific path separators and file operations
10.6. The system SHALL provide consistent behavior across all supported platforms

### 11. Performance Monitoring and Benchmarking

**User Story**: As a performance engineer, I want detailed performance metrics, so that I can optimize and validate the efficiency improvements.

**Acceptance Criteria**:
11.1. The system SHALL report processing rates (combinations per second) for each stage
11.2. The system SHALL track memory usage throughout the entire process
11.3. The system SHALL measure and report database I/O performance
11.4. The system SHALL provide timing breakdowns for major processing phases
11.5. The system SHALL support performance profiling and benchmarking modes
11.6. The system SHALL include automated performance regression tests

### 12. Data Migration and Compatibility

**User Story**: As a poker AI developer with existing data, I want seamless migration from Python-generated databases, so that I can leverage previous computational work.

**Acceptance Criteria**:
12.1. The system SHALL read databases created by the Python implementation
12.2. The system SHALL resume processing from partially completed Python-generated checkpoints
12.3. The system SHALL validate database schema compatibility on startup
12.4. The system SHALL provide migration tools for any necessary data format changes
12.5. The system SHALL maintain backward compatibility with existing LUT file formats
12.6. The system SHALL support gradual migration scenarios (Python → Zig stage by stage)