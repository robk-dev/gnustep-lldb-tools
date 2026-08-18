#!/bin/bash
# Two-Stage LLVM/LLDB Build Script for WSL
# Stage 1: Build clang/lld with system compiler
# Stage 2: Build LLDB with stage1 clang
# Author: LLDB GNUstep Team
# Date: 2025

set -euo pipefail

# Dynamic path configuration: the llvm-project checkout is expected to sit
# next to this repo; override with PROJECT_ROOT=... for other layouts.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$REPO_ROOT}"
PROJECT_ROOT="${PROJECT_ROOT:-$(dirname "$REPO_ROOT")/llvm-project}"
if [ ! -d "$PROJECT_ROOT/llvm" ]; then
    echo "ERROR: no LLVM checkout at $PROJECT_ROOT (expected next to this repo)." >&2
    echo "       Set PROJECT_ROOT=/path/to/llvm-project and re-run." >&2
    exit 1
fi

echo "=================================================================================="
echo " LLVM/LLDB Two-Stage Build for WSL"
echo "=================================================================================="
echo "Script Dir:     $SCRIPT_DIR"
echo "Workspace Root: $WORKSPACE_ROOT"
echo "Project Root:   $PROJECT_ROOT"
echo ""

# Build directories
STAGE1_BUILD_DIR="${PROJECT_ROOT}/build-stage1"
BUILD_DIR="${PROJECT_ROOT}/build"

# Build configuration
BUILD_TYPE="RelWithDebInfo"
PARALLEL_JOBS=${PARALLEL_JOBS:-$(nproc)}

# Python configuration for WSL (force Linux Python, not Windows)
# Auto-detect Python version from system
PYTHON3_EXEC="/usr/bin/python3"
PYTHON3_VERSION=$($PYTHON3_EXEC -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
PYTHON3_INC="/usr/include/python${PYTHON3_VERSION}"
PYTHON3_LIB="/usr/lib/x86_64-linux-gnu/libpython${PYTHON3_VERSION}.so"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_stage() {
    echo -e "\n${BLUE}=================================================================================="
    echo -e " $1"
    echo -e "==================================================================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
    exit 1
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Verify Python dev files exist (must run after helpers are defined)
if [ ! -d "$PYTHON3_INC" ]; then
    echo "Install with: sudo apt-get install python${PYTHON3_VERSION}-dev"
    print_error "Python ${PYTHON3_VERSION} headers not found at $PYTHON3_INC"
fi

print_success "Found Python ${PYTHON3_VERSION} headers at $PYTHON3_INC"

# Check prerequisites
check_prerequisites() {
    print_stage "Checking Prerequisites"
    
    # Check for required packages
    local missing_deps=""
    
    if ! command -v ninja &> /dev/null; then
        missing_deps="$missing_deps ninja-build"
    fi
    
    if ! command -v cmake &> /dev/null; then
        missing_deps="$missing_deps cmake"
    fi
    
    if ! command -v ccache &> /dev/null; then
        missing_deps="$missing_deps ccache"
    fi
    
    if [ ! -d "$PYTHON3_INC" ]; then
        missing_deps="$missing_deps python3-dev"
    fi
    
    if ! command -v swig &> /dev/null; then
        missing_deps="$missing_deps swig"
    fi
    
    if [ ! -z "$missing_deps" ]; then
        echo "Please install with: sudo apt-get install$missing_deps"
        print_error "Missing dependencies:$missing_deps"
    fi
    
    print_success "All prerequisites installed"
    
    # Check disk space (need at least 30GB)
    local available_space=$(df "$PROJECT_ROOT" | awk 'NR==2 {print int($4/1048576)}')
    if [ "$available_space" -lt 30 ]; then
        print_error "Insufficient disk space: ${available_space}GB available, need at least 30GB"
    fi
    print_success "Disk space: ${available_space}GB available"
    
    # Check RAM
    local available_ram=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$available_ram" -lt 8 ]; then
        print_warning "Low RAM: ${available_ram}GB available. Build may be slow."
        PARALLEL_JOBS=$((PARALLEL_JOBS / 2))
        print_warning "Reducing parallel jobs to $PARALLEL_JOBS"
    else
        print_success "RAM: ${available_ram}GB available"
    fi
}

# Build Stage 1: Clang and LLD
build_stage1() {
    print_stage "Stage 1: Building Clang and LLD"
    
    if [ -f "$STAGE1_BUILD_DIR/bin/clang" ] && [ -f "$STAGE1_BUILD_DIR/bin/ld.lld" ]; then
        print_success "Stage 1 already built (found clang and lld)"
        echo "To rebuild, remove: $STAGE1_BUILD_DIR"
        return 0
    fi
    
    mkdir -p "$STAGE1_BUILD_DIR"
    cd "$STAGE1_BUILD_DIR"
    
    echo "Configuring Stage 1 build..."
    cmake -G Ninja ../llvm \
        -DCMAKE_BUILD_TYPE=Release \
        -DLLVM_ENABLE_PROJECTS="clang;lld" \
        -DLLVM_TARGETS_TO_BUILD="X86" \
        -DLLVM_ENABLE_ASSERTIONS=OFF \
        -DBUILD_SHARED_LIBS=OFF \
        -DLLVM_CCACHE_BUILD=ON \
        -DLLVM_INCLUDE_TESTS=OFF \
        -DLLVM_INCLUDE_EXAMPLES=OFF \
        -DLLVM_INCLUDE_DOCS=OFF
    
    echo "Building clang and lld (this may take 20-40 minutes)..."
    ninja clang lld llvm-tblgen clang-tblgen -j${PARALLEL_JOBS}
    
    if [ ! -f "$STAGE1_BUILD_DIR/bin/clang" ]; then
        print_error "Stage 1 build failed: clang not found"
    fi
    
    if [ ! -f "$STAGE1_BUILD_DIR/bin/ld.lld" ]; then
        print_error "Stage 1 build failed: lld not found"
    fi
    
    print_success "Stage 1 complete: clang and lld built successfully"
}

# Build Stage 2: LLDB with Stage 1 Clang
build_stage2() {
    print_stage "Stage 2: Building LLDB with Stage 1 Clang"
    
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    
    # Check if we need to reconfigure
    if [ -f "CMakeCache.txt" ]; then
        local current_compiler=$(grep "CMAKE_CXX_COMPILER:FILEPATH" CMakeCache.txt | cut -d= -f2)
        if [ "$current_compiler" != "$STAGE1_BUILD_DIR/bin/clang++" ]; then
            print_warning "Compiler changed, removing CMakeCache.txt"
            rm -f CMakeCache.txt
        fi
    fi
    
    echo "Configuring Stage 2 build..."
    echo "Using clang from: $STAGE1_BUILD_DIR/bin/clang"
    echo "Using Python from: $PYTHON3_EXEC"
    
    # Export stage1 tools for tablegen
    export LLVM_TABLEGEN="$STAGE1_BUILD_DIR/bin/llvm-tblgen"
    export CLANG_TABLEGEN="$STAGE1_BUILD_DIR/bin/clang-tblgen"
    
    cmake -G Ninja ../llvm \
        -DCMAKE_C_COMPILER="$STAGE1_BUILD_DIR/bin/clang" \
        -DCMAKE_CXX_COMPILER="$STAGE1_BUILD_DIR/bin/clang++" \
        -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
        -DLLVM_ENABLE_PROJECTS="clang;lldb;lld" \
        -DLLVM_ENABLE_ASSERTIONS=ON \
        -DLLDB_INCLUDE_TESTS=ON \
        -DBUILD_SHARED_LIBS=ON \
        -DLLVM_CCACHE_BUILD=ON \
        -DLLDB_ENABLE_PYTHON=ON \
        -DPython3_EXECUTABLE="$PYTHON3_EXEC" \
        -DPython3_INCLUDE_DIRS="$PYTHON3_INC" \
        -DPython3_LIBRARIES="$PYTHON3_LIB" \
        -DLLDB_PYTHON_HOME="/usr" \
        -DLLDB_ENABLE_LIBEDIT=ON \
        -DLLDB_ENABLE_CURSES=ON \
        -DLLVM_TABLEGEN="$LLVM_TABLEGEN" \
        -DCLANG_TABLEGEN="$CLANG_TABLEGEN" \
        -DLLVM_USE_LINKER="$STAGE1_BUILD_DIR/bin/ld.lld" \
        -DLLVM_TARGETS_TO_BUILD="X86" \
        -DLLVM_PARALLEL_LINK_JOBS=4 \
        -DLLDB_TEST_OBJC_GNUSTEP=On \
        -DLLDB_TEST_OBJC_GNUSTEP_DIR=/usr/local \
        -DCMAKE_INSTALL_PREFIX="/usr/local/llvm-reldeb"
    
    echo "Building LLDB and lldb-server (this may take 30-60 minutes)..."
    # clang is needed so the lit test suites (%build) use the in-tree compiler
    ninja lldb lldb-server clang -j${PARALLEL_JOBS}
    
    if [ ! -f "$BUILD_DIR/bin/lldb" ]; then
        print_error "Stage 2 build failed: lldb not found"
    fi
    
    if [ ! -f "$BUILD_DIR/bin/lldb-server" ]; then
        print_error "Stage 2 build failed: lldb-server not found"
    fi
    
    print_success "Stage 2 complete: LLDB and lldb-server built successfully"
}

# Verify the build
verify_build() {
    print_stage "Verifying Build"
    
    # Check Python support
    echo -n "Checking Python support... "
    local python_path=$("$BUILD_DIR/bin/lldb" -P 2>/dev/null || echo "")
    if [ -z "$python_path" ]; then
        print_error "Python support not working!"
    else
        print_success "Python enabled: $python_path"
    fi
    
    # Check lldb-server
    echo -n "Checking lldb-server... "
    if "$BUILD_DIR/bin/lldb-server" version >/dev/null 2>&1; then
        print_success "lldb-server working"
    else
        print_error "lldb-server not working!"
    fi
    
    # Check GNUstep plugin
    echo -n "Checking GNUstep plugin... "
    if [ -f "$BUILD_DIR/lib/liblldbPluginGNUstepObjCRuntime.so" ]; then
        print_success "GNUstep plugin built"
    else
        print_warning "GNUstep plugin not found (may be statically linked)"
    fi
    
    # Quick LLDB test
    echo -n "Testing LLDB basic functionality... "
    if echo "quit" | "$BUILD_DIR/bin/lldb" >/dev/null 2>&1; then
        print_success "LLDB starts successfully"
    else
        print_error "LLDB failed to start!"
    fi
}

# Create helper scripts
create_helpers() {
    print_stage "Creating Helper Scripts"
    
    # Create environment setup script
    cat > "$BUILD_DIR/setup_env.sh" << 'EOF'
#!/bin/bash
# Source this file to set up LLDB environment
export PATH="$(dirname "${BASH_SOURCE[0]}")/bin:$PATH"
export LD_LIBRARY_PATH="$(dirname "${BASH_SOURCE[0]}")/lib:$LD_LIBRARY_PATH"
echo "LLDB environment configured:"
echo "  LLDB: $(which lldb)"
echo "  Clang: $(which clang)"
EOF
    chmod +x "$BUILD_DIR/setup_env.sh"
    
    # Create test script
    cat > "$BUILD_DIR/test_lldb.sh" << 'EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/setup_env.sh"

echo "Testing LLDB with GNUstep..."
# This script lives in llvm-project/build; the tools repo is a sibling of
# llvm-project.
EXAMPLES_DIR="${GNUSTEP_EXAMPLES_DIR:-$SCRIPT_DIR/../../gnustep-lldb-tools/examples}"
if [ ! -d "$EXAMPLES_DIR" ]; then
    EXAMPLES_DIR="$SCRIPT_DIR/../lldb/examples"
fi
cd "$EXAMPLES_DIR"
make clean || true
make CC="$SCRIPT_DIR/bin/clang" custom_class_test
echo ""
echo "Starting LLDB test session..."
echo "Commands to try:"
echo "  b main"
echo "  run"
echo "  po @123"
echo "  po @\"test\""
echo "  quit"
echo ""
lldb ./custom_class_test
EOF
    chmod +x "$BUILD_DIR/test_lldb.sh"
    
    print_success "Helper scripts created"
}

# Show final instructions
show_instructions() {
    print_stage "Build Complete!"
    
    echo -e "${GREEN}Your two-stage LLDB build is ready!${NC}"
    echo ""
    echo "Build locations:"
    echo "  Stage 1 (Bootstrap): $STAGE1_BUILD_DIR"
    echo "  Final Build:         $BUILD_DIR"
    echo ""
    echo "Binaries:"
    echo "  LLDB:        $BUILD_DIR/bin/lldb"
    echo "  lldb-server: $BUILD_DIR/bin/lldb-server"
    echo "  Clang:       $BUILD_DIR/bin/clang"
    echo ""
    echo "To use:"
    echo "  1. Source environment: source $BUILD_DIR/setup_env.sh"
    echo "  2. Test LLDB:         $BUILD_DIR/test_lldb.sh"
    echo ""
    echo "For development:"
    echo "  cd $BUILD_DIR && ninja lldb lldb-server  # Incremental rebuild"
    echo ""
    echo -e "${BLUE}Built with:${NC}"
    echo "  • Stage 1 clang (bootstrap compiler)"
    echo "  • Python support enabled (WSL Python)"
    echo "  • Shared libraries for fast rebuilds"
    echo "  • GNUstep ObjC runtime plugin"
}

# Main execution
main() {
    # Parse arguments
    SKIP_STAGE1=false
    SKIP_STAGE2=false
    CLEAN_BUILD=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-stage1)
                SKIP_STAGE1=true
                shift
                ;;
            --skip-stage2)
                SKIP_STAGE2=true
                shift
                ;;
            --clean)
                CLEAN_BUILD=true
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --skip-stage1   Skip building stage 1 (use existing)"
                echo "  --skip-stage2   Skip building stage 2 (stage 1 only)"
                echo "  --clean         Clean build directories before starting"
                echo "  --help          Show this help"
                echo ""
                echo "Environment variables:"
                echo "  PARALLEL_JOBS   Number of parallel build jobs (default: nproc)"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                ;;
        esac
    done
    
    # Clean if requested
    if $CLEAN_BUILD; then
        print_warning "Cleaning build directories..."
        rm -rf "$STAGE1_BUILD_DIR" "$BUILD_DIR"
    fi
    
    # Run build stages
    check_prerequisites
    
    if ! $SKIP_STAGE1; then
        build_stage1
    else
        if [ ! -f "$STAGE1_BUILD_DIR/bin/clang" ]; then
            print_error "Stage 1 not found. Cannot skip stage 1."
        fi
        print_success "Skipping Stage 1 (using existing)"
    fi
    
    if ! $SKIP_STAGE2; then
        build_stage2
        verify_build
        create_helpers
        show_instructions
    else
        print_success "Skipping Stage 2"
    fi
    
    print_success "Build script completed successfully!"
}

# Run main function
main "$@"