#!/bin/bash
# Release build script for Poker AI
# Builds Python wheels and Zig binaries for distribution

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/build"
DIST_DIR="$PROJECT_ROOT/dist"
ZIG_DIR="$PROJECT_ROOT/poker_ai/zig_clustering"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Check dependencies
check_dependencies() {
    log_info "Checking build dependencies..."
    
    # Check for required tools
    local missing_deps=()
    
    if ! command -v python3 &> /dev/null; then
        missing_deps+=("python3")
    fi
    
    if ! command -v zig &> /dev/null; then
        missing_deps+=("zig")
    fi
    
    if ! command -v git &> /dev/null; then
        missing_deps+=("git")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        exit 1
    fi
    
    # Check Python version
    python_version=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    if [[ ! "$python_version" =~ ^3\.(9|10|11|12)$ ]]; then
        log_warn "Python version $python_version may not be supported (recommended: 3.9-3.12)"
    fi
    
    # Check Zig version
    zig_version=$(zig version)
    log_info "Using Zig version: $zig_version"
    
    log_success "All dependencies found"
}

# Clean previous builds
clean_build() {
    log_info "Cleaning previous builds..."
    
    rm -rf "$BUILD_DIR" "$DIST_DIR"
    mkdir -p "$BUILD_DIR" "$DIST_DIR"
    
    # Clean Zig build artifacts
    if [ -d "$ZIG_DIR/zig-out" ]; then
        rm -rf "$ZIG_DIR/zig-out"
    fi
    
    # Clean Python build artifacts
    find "$PROJECT_ROOT" -name "*.pyc" -delete
    find "$PROJECT_ROOT" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
    find "$PROJECT_ROOT" -name "*.egg-info" -type d -exec rm -rf {} + 2>/dev/null || true
    
    log_success "Build directories cleaned"
}

# Build Zig clustering component
build_zig_component() {
    log_info "Building Zig clustering component..."
    
    cd "$ZIG_DIR"
    
    # Build optimized release
    zig build -Doptimize=ReleaseFast
    
    # Copy binary to dist
    if [ -f "zig-out/bin/poker_clustering" ]; then
        cp "zig-out/bin/poker_clustering" "$DIST_DIR/"
        log_success "Zig binary built successfully"
    else
        log_error "Zig binary not found after build"
        exit 1
    fi
    
    cd "$PROJECT_ROOT"
}

# Build Python package
build_python_package() {
    log_info "Building Python package..."
    
    cd "$PROJECT_ROOT"
    
    # Install build dependencies
    python3 -m pip install --upgrade pip build wheel setuptools
    
    # Build source distribution and wheel
    python3 -m build
    
    # Verify wheel contents
    if ls dist/*.whl 1> /dev/null 2>&1; then
        log_success "Python wheel built successfully"
        log_info "Wheel contents:"
        python3 -m zipfile -l dist/*.whl | head -20
    else
        log_error "Python wheel not found after build"
        exit 1
    fi
}

# Run tests
run_tests() {
    log_info "Running test suite..."
    
    cd "$PROJECT_ROOT"
    
    # Install package in development mode
    python3 -m pip install -e .
    
    # Run Python tests
    if command -v pytest &> /dev/null; then
        python3 -m pytest test/ -v --tb=short
    else
        log_warn "pytest not found, running basic import test"
        python3 -c "import poker_ai; print('Python package imports successfully')"
    fi
    
    # Test Zig binary
    if [ -f "$DIST_DIR/poker_clustering" ]; then
        "$DIST_DIR/poker_clustering" --help > /dev/null
        log_success "Zig binary executes successfully"
    fi
    
    log_success "All tests passed"
}

# Generate release artifacts
generate_artifacts() {
    log_info "Generating release artifacts..."
    
    cd "$PROJECT_ROOT"
    
    # Get version from pyproject.toml
    version=$(python3 -c "import tomllib; print(tomllib.load(open('pyproject.toml', 'rb'))['project']['version'])")
    
    # Create release directory
    release_dir="$DIST_DIR/poker-ai-$version"
    mkdir -p "$release_dir"
    
    # Copy artifacts
    if ls dist/*.whl 1> /dev/null 2>&1; then
        cp dist/*.whl "$release_dir/"
    fi
    
    if ls dist/*.tar.gz 1> /dev/null 2>&1; then
        cp dist/*.tar.gz "$release_dir/"
    fi
    
    if [ -f "$DIST_DIR/poker_clustering" ]; then
        cp "$DIST_DIR/poker_clustering" "$release_dir/"
    fi
    
    # Copy documentation
    cp README.md HISTORY.md LICENSE "$release_dir/"
    
    # Create release notes
    cat > "$release_dir/RELEASE_NOTES.md" << EOF
# Poker AI Release $version

## Components

- \`poker-ai-$version-py3-none-any.whl\` - Python package wheel
- \`poker-ai-$version.tar.gz\` - Python source distribution  
- \`poker_clustering\` - Zig clustering binary (Linux x86_64)

## Installation

### Python Package
\`\`\`bash
pip install poker-ai-$version-py3-none-any.whl
\`\`\`

### Zig Binary
\`\`\`bash
chmod +x poker_clustering
./poker_clustering --help
\`\`\`

## System Requirements

- Python 3.9+ (for Python package)
- SQLite3 (for clustering binary)
- Linux x86_64 (for clustering binary)

## Usage

See README.md for detailed usage instructions.
EOF

    # Create checksums
    cd "$release_dir"
    sha256sum * > SHA256SUMS
    
    log_success "Release artifacts generated in $release_dir"
}

# Print summary
print_summary() {
    log_info "Build Summary"
    echo "=============="
    
    if [ -d "$DIST_DIR" ]; then
        echo "Artifacts in $DIST_DIR:"
        find "$DIST_DIR" -type f -exec ls -lh {} \; | awk '{print $9 " (" $5 ")"}'
    fi
    
    echo ""
    log_success "Release build completed successfully!"
    echo "Next steps:"
    echo "1. Test the artifacts in a clean environment"
    echo "2. Upload to PyPI: twine upload dist/*.whl dist/*.tar.gz"
    echo "3. Create GitHub release with artifacts from dist/"
}

# Main execution
main() {
    log_info "Starting Poker AI release build..."
    
    check_dependencies
    clean_build
    build_zig_component
    build_python_package
    run_tests
    generate_artifacts
    print_summary
}

# Handle script arguments
case "${1:-all}" in
    "clean")
        clean_build
        ;;
    "zig")
        build_zig_component
        ;;
    "python")
        build_python_package
        ;;
    "test")
        run_tests
        ;;
    "artifacts")
        generate_artifacts
        ;;
    "all"|*)
        main
        ;;
esac