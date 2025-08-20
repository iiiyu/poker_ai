#!/bin/bash
# Cross-compilation script for Poker AI Zig clustering component
# Builds binaries for multiple platforms

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ZIG_DIR="$PROJECT_ROOT/poker_ai/zig_clustering"
DIST_DIR="$PROJECT_ROOT/dist"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Target platforms
declare -A TARGETS=(
    ["linux-x86_64"]="x86_64-linux-gnu"
    ["linux-aarch64"]="aarch64-linux-gnu"
    ["macos-x86_64"]="x86_64-macos-none"
    ["macos-aarch64"]="aarch64-macos-none"
    ["windows-x86_64"]="x86_64-windows-gnu"
)

# Check dependencies
check_zig() {
    if ! command -v zig &> /dev/null; then
        log_error "Zig compiler not found. Please install Zig 0.13.0 or later."
        exit 1
    fi
    
    local zig_version
    zig_version=$(zig version)
    log_info "Using Zig version: $zig_version"
}

# Clean previous builds
clean_builds() {
    log_info "Cleaning previous cross-compilation builds..."
    
    rm -rf "$DIST_DIR/cross-compile"
    mkdir -p "$DIST_DIR/cross-compile"
    
    if [ -d "$ZIG_DIR/zig-out" ]; then
        rm -rf "$ZIG_DIR/zig-out"
    fi
}

# Build for specific target
build_target() {
    local target_name="$1"
    local zig_target="$2"
    
    log_info "Building for $target_name ($zig_target)..."
    
    cd "$ZIG_DIR"
    
    # Create target-specific output directory
    local output_dir="$DIST_DIR/cross-compile/$target_name"
    mkdir -p "$output_dir"
    
    # Determine binary extension
    local binary_name="poker_clustering"
    if [[ "$target_name" == *"windows"* ]]; then
        binary_name="poker_clustering.exe"
    fi
    
    # Build for target
    if zig build -Dtarget="$zig_target" -Doptimize=ReleaseFast --prefix="$output_dir"; then
        # Check if binary was created
        local expected_binary="$output_dir/bin/$binary_name"
        if [ -f "$expected_binary" ]; then
            log_success "Built $target_name successfully"
            
            # Get binary size
            local size
            size=$(ls -lh "$expected_binary" | awk '{print $5}')
            log_info "Binary size: $size"
            
            # Test basic execution (skip for cross-compiled binaries that can't run on host)
            if [[ "$target_name" == "linux-x86_64" ]] && [[ "$(uname -s)" == "Linux" ]]; then
                if "$expected_binary" --help > /dev/null 2>&1; then
                    log_success "Binary executes successfully"
                else
                    log_error "Binary execution test failed"
                    return 1
                fi
            elif [[ "$target_name" == "macos-"* ]] && [[ "$(uname -s)" == "Darwin" ]]; then
                if "$expected_binary" --help > /dev/null 2>&1; then
                    log_success "Binary executes successfully"
                else
                    log_error "Binary execution test failed"
                    return 1
                fi
            fi
            
            return 0
        else
            log_error "Expected binary not found: $expected_binary"
            return 1
        fi
    else
        log_error "Build failed for $target_name"
        return 1
    fi
}

# Build all targets
build_all_targets() {
    local failed_targets=()
    local successful_targets=()
    
    for target_name in "${!TARGETS[@]}"; do
        if build_target "$target_name" "${TARGETS[$target_name]}"; then
            successful_targets+=("$target_name")
        else
            failed_targets+=("$target_name")
        fi
        echo ""
    done
    
    # Summary
    log_info "Cross-compilation Summary"
    echo "========================="
    
    if [ ${#successful_targets[@]} -gt 0 ]; then
        log_success "Successful builds:"
        for target in "${successful_targets[@]}"; do
            echo "  ✓ $target"
        done
    fi
    
    if [ ${#failed_targets[@]} -gt 0 ]; then
        log_error "Failed builds:"
        for target in "${failed_targets[@]}"; do
            echo "  ✗ $target"
        done
    fi
    
    echo ""
    log_info "Build artifacts in: $DIST_DIR/cross-compile/"
}

# Create release package
create_release_package() {
    log_info "Creating cross-platform release package..."
    
    local version
    version=$(python3 -c "import tomllib; print(tomllib.load(open('$PROJECT_ROOT/pyproject.toml', 'rb'))['project']['version'])" 2>/dev/null || echo "dev")
    
    local release_dir="$DIST_DIR/poker-clustering-$version-cross-platform"
    mkdir -p "$release_dir"
    
    # Copy all successful builds
    for target_name in "${!TARGETS[@]}"; do
        local target_dir="$DIST_DIR/cross-compile/$target_name"
        if [ -d "$target_dir/bin" ]; then
            mkdir -p "$release_dir/$target_name"
            cp -r "$target_dir/bin"/* "$release_dir/$target_name/"
        fi
    done
    
    # Create installation script
    cat > "$release_dir/install.sh" << 'EOF'
#!/bin/bash
# Installation script for poker_clustering

set -euo pipefail

# Detect platform
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
    Linux*)
        case "$ARCH" in
            x86_64) PLATFORM="linux-x86_64" ;;
            aarch64|arm64) PLATFORM="linux-aarch64" ;;
            *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
        esac
        BINARY_NAME="poker_clustering"
        ;;
    Darwin*)
        case "$ARCH" in
            x86_64) PLATFORM="macos-x86_64" ;;
            arm64) PLATFORM="macos-aarch64" ;;
            *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
        esac
        BINARY_NAME="poker_clustering"
        ;;
    CYGWIN*|MINGW*|MSYS*)
        PLATFORM="windows-x86_64"
        BINARY_NAME="poker_clustering.exe"
        ;;
    *)
        echo "Unsupported OS: $OS"
        exit 1
        ;;
esac

echo "Detected platform: $PLATFORM"

# Check if binary exists
BINARY_PATH="$PLATFORM/$BINARY_NAME"
if [ ! -f "$BINARY_PATH" ]; then
    echo "Binary not found for platform $PLATFORM"
    echo "Available platforms:"
    ls -1 | grep -v install.sh | grep -v README.md || echo "None"
    exit 1
fi

# Install binary
INSTALL_DIR="${1:-$HOME/.local/bin}"
mkdir -p "$INSTALL_DIR"

cp "$BINARY_PATH" "$INSTALL_DIR/poker_clustering"
chmod +x "$INSTALL_DIR/poker_clustering"

echo "poker_clustering installed to $INSTALL_DIR/poker_clustering"
echo "Make sure $INSTALL_DIR is in your PATH"

# Test installation
if command -v poker_clustering &> /dev/null; then
    echo "Installation successful!"
    poker_clustering --help
else
    echo "Binary installed but not in PATH. Add $INSTALL_DIR to your PATH:"
    echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
fi
EOF
    
    chmod +x "$release_dir/install.sh"
    
    # Create README
    cat > "$release_dir/README.md" << EOF
# Poker AI Clustering Component - Cross-Platform Binaries

This package contains pre-compiled binaries of the poker_clustering component for multiple platforms.

## Installation

Run the installation script:
\`\`\`bash
./install.sh [install_directory]
\`\`\`

Default install directory is \`\$HOME/.local/bin\`.

## Manual Installation

1. Choose the appropriate binary for your platform:
   - \`linux-x86_64/poker_clustering\` - Linux x86_64
   - \`linux-aarch64/poker_clustering\` - Linux ARM64
   - \`macos-x86_64/poker_clustering\` - macOS Intel
   - \`macos-aarch64/poker_clustering\` - macOS Apple Silicon
   - \`windows-x86_64/poker_clustering.exe\` - Windows x86_64

2. Copy to a directory in your PATH
3. Make executable (Unix-like systems): \`chmod +x poker_clustering\`

## Usage

\`\`\`bash
poker_clustering --help
\`\`\`

## Requirements

- SQLite3 (usually pre-installed on most systems)

## Version

Version: $version
Built with Zig $(zig version 2>/dev/null || echo "unknown")
EOF
    
    # Create checksums
    cd "$release_dir"
    find . -name "poker_clustering*" -type f -exec sha256sum {} \; > SHA256SUMS
    
    log_success "Cross-platform release package created: $release_dir"
}

# Main execution
main() {
    log_info "Starting cross-compilation for poker_clustering..."
    
    check_zig
    clean_builds
    build_all_targets
    create_release_package
    
    log_success "Cross-compilation completed!"
}

# Handle script arguments
case "${1:-all}" in
    "clean")
        clean_builds
        ;;
    "linux-x86_64"|"linux-aarch64"|"macos-x86_64"|"macos-aarch64"|"windows-x86_64")
        if [[ -n "${TARGETS[$1]:-}" ]]; then
            clean_builds
            build_target "$1" "${TARGETS[$1]}"
        else
            log_error "Unknown target: $1"
            exit 1
        fi
        ;;
    "package")
        create_release_package
        ;;
    "all"|*)
        main
        ;;
esac