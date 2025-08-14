# Poker AI - Modern Python Setup with UV

This project has been refactored to use modern Python tooling with `uv` package manager and Python 3.12.

## What's Changed

### 1. **Modern Python Packaging**
- Migrated from `setup.py` to `pyproject.toml` (PEP 517/518 compliant)
- Uses `uv` for fast, reliable dependency management
- Python 3.12.7 as the default version (specified in `.python-version`)

### 2. **Improved Dependencies**
- Updated all dependencies to latest compatible versions
- Added missing Flask dependencies for visualization
- Proper separation of dev dependencies

### 3. **Fixed Multiprocessing Issues**
- Resolved macOS multiprocessing initialization problems
- Proper lazy initialization of multiprocessing managers
- CLI entry point handles multiprocessing setup correctly

### 4. **Developer Experience**
- Added comprehensive `Makefile` for common tasks
- Integrated linting (ruff), formatting (black), and type checking (mypy)
- Improved test configuration with coverage reporting

## Quick Start

### Prerequisites
1. Install `uv` package manager:
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

2. Clone the repository:
```bash
git clone https://github.com/fedden/poker_ai.git
cd poker_ai
```

### Installation
```bash
# Install dependencies
make install

# Or for development (includes test/lint tools)
make install-dev
```

### Usage

All the original functionality is preserved:

```bash
# Generate card information lookup tables (required before training)
uv run poker_ai cluster

# Train a new agent
uv run poker_ai train start

# Play against trained agent
uv run poker_ai play

# Visualize bot strategy
uv run poker_ai viz
```

Or use the Makefile shortcuts:
```bash
make run-cluster  # Generate lookup tables
make run-train    # Start training
make run-play     # Play against AI
make run-viz      # Visualize strategy
```

### Development

```bash
# Run tests
make test

# Run tests with coverage
make test-coverage

# Lint code
make lint

# Format code
make format

# Build documentation
make docs

# Clean build artifacts
make clean
```

## Key Files

- **`pyproject.toml`**: Modern Python project configuration
- **`.python-version`**: Specifies Python 3.12.7 for the project
- **`Makefile`**: Developer convenience commands
- **`uv.lock`**: Locked dependency versions for reproducibility

## Benefits of UV

1. **Speed**: 10-100x faster than pip
2. **Reliability**: Deterministic dependency resolution
3. **Simplicity**: Single tool for package and Python version management
4. **Compatibility**: Works with standard Python packaging

## Migration Notes

- All original logic and functionality preserved
- Import structure unchanged
- CLI commands remain the same
- Tests continue to work as before

The refactoring focused solely on modernizing the build system and dependency management while keeping all poker AI logic intact.