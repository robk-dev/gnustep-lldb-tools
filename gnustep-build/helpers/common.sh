#!/bin/bash
# Common utilities and functions for LLVM/LLDB build scripts
# Author: GitHub Copilot
# Date: July 31, 2025

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# NOTE: Path configuration - set defaults if not already defined by parent
# script. The llvm-project checkout is expected to sit next to this repo;
# override with PROJECT_ROOT=... for other layouts.
if [ -z "${WORKSPACE_ROOT:-}" ]; then
    # Determine paths relative to this script
    HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SCRIPT_DIR="$(dirname "$HELPERS_DIR")"           # .../gnustep-build
    WORKSPACE_ROOT="$(dirname "$SCRIPT_DIR")"        # tools repo root
    PROJECT_ROOT="${PROJECT_ROOT:-$(dirname "$WORKSPACE_ROOT")/llvm-project}"
fi
if [ ! -d "$PROJECT_ROOT/llvm" ]; then
    echo "WARNING: no LLVM checkout at $PROJECT_ROOT (expected next to this repo)." >&2
    echo "         Set PROJECT_ROOT=/path/to/llvm-project if this is unexpected." >&2
fi

# Calculate safe parallel jobs based on available memory
# LLVM compilation can use 1-2GB per job, so we need to be conservative
calculate_safe_parallel_jobs() {
    local cpu_cores=$(nproc)
    local mem_gb=$(free -g | awk '/^Mem:/{print $7}')  # Available memory in GB
    local safe_jobs=$((mem_gb / 2))  # Assume 2GB per job
    
    # Use minimum of CPU cores and memory-safe jobs, but at least 2
    if [ $safe_jobs -lt 2 ]; then
        echo 2
    elif [ $safe_jobs -gt $cpu_cores ]; then
        echo $cpu_cores
    else
        echo $safe_jobs
    fi
}

PARALLEL_JOBS=${PARALLEL_JOBS:-$(calculate_safe_parallel_jobs)}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to print section headers
print_section() {
    echo ""
    echo -e "${BLUE}===============================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}===============================================${NC}"
    echo ""
}

# Function to print progress
print_progress() {
    echo -e "${CYAN}➤ $1${NC}"
}

# Function to print success
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Function to print warning
print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Function to print error and exit
print_error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Function to print info
print_info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

# Function to show build status (inspired by build_incremental.sh)
show_build_status() {
    print_progress "Build Status Summary"
    echo "===================="
    
    local lldb_binary="$LLVM_BUILD_DIR/bin/lldb"
    local lldb_server_binary="$LLVM_BUILD_DIR/bin/lldb-server"
    local clang_binary="$LLVM_BUILD_DIR/bin/clang"
    local plugin_dir="$PROJECT_ROOT/lldb/source/Plugins/LanguageRuntime/ObjC/GNUstepObjCRuntime"
    
    if [ -f "$lldb_binary" ]; then
        local lldb_date=$(date -r "$lldb_binary" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
        local lldb_version=$("$lldb_binary" --version 2>/dev/null | head -1 || echo "Version check failed")
        print_success "LLDB binary: $lldb_binary (built: $lldb_date)"
        echo "             Version: $lldb_version"
    else
        print_warning "LLDB binary not found"
    fi
    
    if [ -f "$lldb_server_binary" ]; then
        local server_date=$(date -r "$lldb_server_binary" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
        print_success "LLDB server: $lldb_server_binary (built: $server_date)"
    else
        print_warning "LLDB server not found - this may cause VS Code debugging issues"
    fi
    
    if [ -f "$clang_binary" ]; then
        local clang_date=$(date -r "$clang_binary" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
        print_success "Clang compiler: $clang_binary (built: $clang_date)"
    else
        print_warning "Clang compiler not found"
    fi
    
    if [ -d "$plugin_dir" ]; then
        local file_count=$(find "$plugin_dir" -name "*.cpp" -o -name "*.h" | wc -l)
        print_success "GNUstep plugin files: $file_count files in $plugin_dir"
    else
        print_warning "GNUstep plugin directory not found"
    fi
    
    echo ""
    print_progress "Quick test commands:"
    echo "  $lldb_binary --version"
    echo "  $clang_binary --version"
    if [ -f "$lldb_server_binary" ]; then
        echo "  $lldb_server_binary --help"
    fi
    echo ""
}

# Export color variables for use in other scripts
export RED GREEN YELLOW BLUE CYAN NC
