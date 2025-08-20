# Zig Poker AI Test Framework

This directory contains a comprehensive testing framework for the Zig poker AI implementation, ensuring correctness, performance, and compatibility with the Python reference implementation.

## Test Structure

```
tests/
├── README.md                  # This file
├── test_hand_eval.zig        # Hand evaluation tests
├── test_game_state.zig       # Game logic tests  
├── test_cfr.zig              # MCCFR algorithm tests
├── test_ffi.zig              # Python interop tests
├── integration_test.zig      # Component integration tests
└── test_data/                # Test data files
    ├── hand_rankings.json    # Hand ranking test cases
    └── python_compatibility.json  # Python compatibility specs
```

## Test Categories

### 1. Unit Tests (`test_*.zig`)

- **Hand Evaluation Tests** (`test_hand_eval.zig`)
  - Royal flush, straight flush, four of a kind, etc.
  - Property-based testing for hand ranking order
  - Fuzz testing with random hands
  - Memory efficiency validation

- **Game State Tests** (`test_game_state.zig`) 
  - Game initialization and player management
  - Card dealing and betting actions
  - Showdown resolution and side pot calculation
  - Game state serialization/deserialization

- **CFR Tests** (`test_cfr.zig`)
  - Algorithm convergence testing
  - Exploitability measurement
  - Strategy computation from regrets
  - Monte Carlo CFR sampling
  - Parallel execution safety

- **FFI Tests** (`test_ffi.zig`)
  - C interface functionality
  - Python compatibility validation
  - Data marshalling between languages
  - Performance benchmarking
  - Thread safety verification

### 2. Integration Tests (`integration_test.zig`)

- End-to-end poker game simulation
- Component interaction validation
- Memory consistency across modules
- Error handling propagation
- Performance regression detection

### 3. Property-Based Tests

Embedded within unit tests, these verify invariants:
- Hand rankings maintain proper order
- Strategies sum to valid probability distributions  
- Memory is properly managed
- Floating-point precision is maintained

### 4. Fuzz Tests

Random input testing to catch edge cases:
- Random hand generation and evaluation
- Invalid input handling
- Memory safety under stress
- Concurrent access patterns

## Running Tests

### Quick Test Run
```bash
cd zig
zig build test
```

### Comprehensive Test Suite
```bash
cd zig
./run_tests.sh
```

### Specific Test File
```bash
cd zig
zig test tests/test_hand_eval.zig
```

### With Optimization
```bash
cd zig
zig build test -Doptimize=ReleaseFast
```

### Python Compatibility Validation
```bash
cd ..
python3 validate_zig_python.py
```

## Test Configuration

The test runner script supports various options:

```bash
./run_tests.sh --help
```

Options:
- `--optimize={Debug,ReleaseSafe,ReleaseFast}` - Set optimization level
- `--verbose` - Enable verbose output  
- `--auto-format` - Auto-format code if needed
- `--timeout=SECONDS` - Set timeout for operations

## Continuous Integration

The GitHub Actions workflow (`.github/workflows/zig-tests.yml`) runs:

1. **Test Suite** - All unit and integration tests
2. **Benchmarks** - Performance regression detection  
3. **Memory Safety** - Leak detection and safety checks
4. **Cross Platform** - Windows, macOS, Linux compatibility
5. **Coverage** - Code coverage analysis
6. **Security** - Basic security scanning

## Performance Benchmarks

The benchmark suite (`../bench/main.zig`) measures:

- Hand evaluation speed (ops/sec)
- Equity calculation performance
- Game engine throughput
- CFR iteration speed
- Memory allocation efficiency
- Concurrent execution scaling

### Running Benchmarks

```bash
cd zig
zig build bench -Doptimize=ReleaseFast
./zig-out/bin/poker_ai_bench
```

## Python Compatibility

The validation system ensures compatibility with the Python reference:

### Hand Evaluation Compatibility
- Identical rankings for all hand types
- Same card representation format
- Consistent edge case handling

### Floating-Point Precision  
- CFR calculations within tolerance
- Equity values match Python output
- No accumulation of numerical errors

### Data Structure Compatibility
- Same clustering results
- Identical LUT generation
- Compatible serialization formats

## Test Data

### Hand Rankings (`test_data/hand_rankings.json`)
Contains test cases with expected hand rankings:
- All hand types from royal flush to high card
- Edge cases like wheel straights
- Property test specifications

### Python Compatibility (`test_data/python_compatibility.json`)
Defines compatibility requirements:
- Floating-point tolerances
- Performance benchmarks
- Memory usage limits
- Expected behavior specifications

## Writing New Tests

### Unit Test Template

```zig
const std = @import("std");
const testing = std.testing;
const poker_ai = @import("poker_ai");

const allocator = testing.allocator;

test "descriptive test name" {
    // Arrange
    var component = try Component.init(allocator);
    defer component.deinit();
    
    // Act
    const result = component.performAction();
    
    // Assert
    try testing.expect(result.isValid());
    try testing.expectEqual(expected_value, result.value);
}
```

### Property-Based Test Template

```zig
test "property invariant holds" {
    var prng = std.rand.DefaultPrng.init(42);
    const random = prng.random();
    
    // Test 100 random inputs
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const input = generateRandomInput(random);
        const result = processInput(input);
        
        // Verify invariant
        try testing.expect(invariantHolds(result));
    }
}
```

### Integration Test Template

```zig
test "component integration" {
    var component_a = try ComponentA.init(allocator);
    defer component_a.deinit();
    
    var component_b = try ComponentB.init(allocator);
    defer component_b.deinit();
    
    // Test interaction
    const data = component_a.produceData();
    const result = component_b.processData(data);
    
    try testing.expect(result.isConsistent());
}
```

## Best Practices

### Test Organization
- One test file per module
- Clear, descriptive test names
- Arrange-Act-Assert structure
- Proper resource cleanup

### Performance Testing
- Use `ReleaseFast` for benchmarks
- Measure ops/sec, not just time
- Test memory usage patterns
- Validate against baselines

### Error Testing  
- Test all error conditions
- Verify error propagation
- Check resource cleanup on errors
- Validate error messages

### Compatibility Testing
- Compare with Python results
- Test data format compatibility
- Verify numerical precision
- Check serialization formats

## Troubleshooting

### Common Issues

**Build Failures**
- Ensure Zig 0.13.0+ is installed
- Check SQLite3 development libraries
- Verify all source files compile

**Test Timeouts**
- Increase timeout with `--timeout` flag
- Check for infinite loops
- Optimize test algorithms

**Memory Errors**
- Run with `-Doptimize=Debug`
- Use built-in leak detection
- Check allocator usage patterns

**Compatibility Failures**
- Verify Python environment setup
- Check floating-point tolerances
- Compare algorithm implementations

### Getting Help

1. Check test output for specific error messages
2. Run with `--verbose` for detailed information
3. Compare with working Python implementation
4. Review test data for expected behavior
5. Check CI logs for environment differences

## Contributing

When adding new features:

1. Write tests first (TDD approach)
2. Include unit, integration, and property tests
3. Add benchmark cases for performance-critical code
4. Validate Python compatibility
5. Update test data files as needed
6. Run full test suite before submitting

The test framework is designed to catch regressions early and ensure the Zig implementation maintains compatibility with the Python reference while providing superior performance.