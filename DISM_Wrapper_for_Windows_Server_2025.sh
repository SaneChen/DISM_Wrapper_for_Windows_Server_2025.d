#!/bin/bash
#
# compile-dism-wrapper.sh
# Cross-compile DISM wrapper on Linux for Windows Server 2025
#
# Requirements:
#   sudo apt install mingw-w64
#
# Usage: ./compile-dism-wrapper.sh [clean|rebuild]

set -e

SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
BUILD_DIR="${SCRIPT_DIR}/build"
SOURCE_FILE="${SCRIPT_DIR}/dism-wrapper.c"
OUTPUT_FILE="${BUILD_DIR}/dism.exe"

# Compiler configuration
MINGW_64="x86_64-w64-mingw32-gcc"
MINGW_32="i686-w64-mingw32-gcc"

# Compiler flags
CFLAGS="-std=c11 -Wall -Wextra -Wpedantic -Werror -O2 -static"
LDFLAGS="-s -static -D_WIN32_WINNT=0x0A00"  # Windows 10/Server 2016+

# Display usage information
show_usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTION]

Options:
  clean     Remove build artifacts
  rebuild   Clean and rebuild
  help      Display this help message

Without options, compiles the wrapper if source is newer than output.

Environment variables:
  CC_64     Override 64-bit compiler (default: ${MINGW_64})
  CC_32     Override 32-bit compiler (default: ${MINGW_32})
EOF
}

# Check for required tools
check_dependencies() {
    echo "Checking dependencies..."
    
    # Check for MinGW compilers
    if [ -n "${CC_64}" ]; then
        if ! command -v "${CC_64}" > /dev/null 2>&1; then
            echo "ERROR: Specified 64-bit compiler not found: ${CC_64}"
            exit 1
        fi
    else
        if ! command -v "${MINGW_64}" > /dev/null 2>&1; then
            echo "ERROR: MinGW-w64 not found. Install with:"
            echo "  sudo apt install mingw-w64"
            exit 1
        fi
        CC_64="${MINGW_64}"
    fi
    
    if [ -n "${CC_32}" ]; then
        if ! command -v "${CC_32}" > /dev/null 2>&1; then
            echo "ERROR: Specified 32-bit compiler not found: ${CC_32}"
            exit 1
        fi
    else
        CC_32="${MINGW_32}"
    fi
    
    echo "✓ Using 64-bit compiler: ${CC_64}"
    if command -v "${CC_32}" > /dev/null 2>&1; then
        echo "✓ Using 32-bit compiler: ${CC_32}"
    else
        echo "⚠ 32-bit compiler not available"
    fi
}

# Create build directory
create_build_dir() {
    if [ ! -d "${BUILD_DIR}" ]; then
        echo "Creating build directory: ${BUILD_DIR}"
        mkdir -p "${BUILD_DIR}"
    fi
}

# Clean build artifacts
clean_build() {
    echo "Cleaning build artifacts..."
    if [ -d "${BUILD_DIR}" ]; then
        rm -rf "${BUILD_DIR}"
        echo "✓ Build directory removed"
    else
        echo "⚠ Build directory does not exist"
    fi
}

# Verify source file exists
check_source() {
    if [ ! -f "${SOURCE_FILE}" ]; then
        echo "ERROR: Source file not found: ${SOURCE_FILE}"
        exit 1
    fi
    
    echo "✓ Source file found: ${SOURCE_FILE}"
    
    # Check file size
    FILE_SIZE=$(stat -c%s "${SOURCE_FILE}" 2>/dev/null || stat -f%z "${SOURCE_FILE}" 2>/dev/null)
    if [ "${FILE_SIZE}" -lt 100 ]; then
        echo "WARNING: Source file appears very small (${FILE_SIZE} bytes)"
    fi
}

# Compile for 64-bit Windows
compile_64bit() {
    local output="${BUILD_DIR}/dism-x64.exe"
    local compiler="${CC_64}"
    
    echo "Compiling 64-bit version..."
    echo "Compiler: ${compiler}"
    echo "Output: ${output}"
    
    "${compiler}" ${CFLAGS} ${LDFLAGS} \
        -o "${output}" \
        "${SOURCE_FILE}"
    
    if [ $? -eq 0 ]; then
        echo "✓ 64-bit compilation successful"
        
        # Verify the output
        if command -v file > /dev/null 2>&1; then
            file "${output}"
        fi
        
        # Show file size
        local size=$(stat -c%s "${output}" 2>/dev/null || stat -f%z "${output}" 2>/dev/null)
        echo "File size: $((size / 1024)) KB"
        
        # Create symbolic link as dism.exe
        ln -sf "dism-x64.exe" "${OUTPUT_FILE}"
    else
        echo "✗ 64-bit compilation failed"
        return 1
    fi
}

# Compile for 32-bit Windows
compile_32bit() {
    if ! command -v "${CC_32}" > /dev/null 2>&1; then
        echo "⚠ Skipping 32-bit compilation (compiler not available)"
        return 0
    fi
    
    local output="${BUILD_DIR}/dism-x86.exe"
    local compiler="${CC_32}"
    
    echo "Compiling 32-bit version..."
    echo "Compiler: ${compiler}"
    echo "Output: ${output}"
    
    "${compiler}" ${CFLAGS} ${LDFLAGS} \
        -o "${output}" \
        "${SOURCE_FILE}"
    
    if [ $? -eq 0 ]; then
        echo "✓ 32-bit compilation successful"
        
        # Verify the output
        if command -v file > /dev/null 2>&1; then
            file "${output}"
        fi
        
        # Show file size
        local size=$(stat -c%s "${output}" 2>/dev/null || stat -f%z "${output}" 2>/dev/null)
        echo "File size: $((size / 1024)) KB"
    else
        echo "✗ 32-bit compilation failed"
        return 1
    fi
}

# Generate deployment instructions
generate_deployment_info() {
    cat > "${BUILD_DIR}/DEPLOYMENT.md" << EOF
# DISM Wrapper Deployment Instructions

## Files Generated
- \`dism-x64.exe\` - 64-bit wrapper (recommended for Windows Server 2025)
- \`dism-x86.exe\` - 32-bit wrapper (for compatibility)
- \`dism.exe\` - Symbolic link to 64-bit version

## Deployment Steps

### 1. Backup Original DISM
\`\`\`powershell
# Run as Administrator
cd C:\\Windows\\System32
copy dism.exe dism-backup-\$(Get-Date -Format 'yyyyMMdd').exe
\`\`\`

### 2. Rename Original DISM
\`\`\`powershell
ren dism.exe dism-origin.exe
\`\`\`

### 3. Copy Wrapper
\`\`\`powershell
copy "path\\to\\dism.exe" .
\`\`\`

### 4. Verify Installation
\`\`\`powershell
# Test pass-through
dism /online /get-features | Select-String -Pattern "Feature Name" -First 1

# Test replacement
dism /online /enable-feature /featurename:IIS-LegacySnapIn
# Should show replacement features being installed
\`\`\`

## Verification Commands
\`\`\`powershell
# Check file hashes
Get-FileHash C:\\Windows\\System32\\dism.exe
Get-FileHash C:\\Windows\\System32\\dism-origin.exe

# Check wrapper version
& dism.exe | Select-String -Pattern "Wrapper"
\`\`\`

## Restoring Original Setup
\`\`\`powershell
# Remove wrapper
del C:\\Windows\\System32\\dism.exe

# Restore original
ren dism-origin.exe dism.exe
\`\`\`
EOF
    
    echo "✓ Deployment instructions generated: ${BUILD_DIR}/DEPLOYMENT.md"
}

# Main build function
build() {
    echo "Building DISM wrapper..."
    echo "========================================"
    
    check_dependencies
    create_build_dir
    check_source
    
    # Check if rebuild is needed
    if [ -f "${OUTPUT_FILE}" ] && [ "${SOURCE_FILE}" -ot "${OUTPUT_FILE}" ]; then
        if [ "$1" != "force" ]; then
            echo "✓ Output is up to date. Use '$0 rebuild' to force rebuild."
            return 0
        fi
    fi
    
    # Compile both versions
    compile_64bit
    compile_32bit
    
    # Generate additional files
    generate_deployment_info
    
    echo ""
    echo "========================================"
    echo "Build completed successfully!"
    echo "Output directory: ${BUILD_DIR}"
    echo ""
    
    # Show final file list
    echo "Generated files:"
    ls -la "${BUILD_DIR}/"*.exe 2>/dev/null | awk '{print "  " $9 " (" $5 " bytes)"}'
}

# Parse command line arguments
case "$1" in
    clean)
        clean_build
        ;;
    rebuild)
        clean_build
        build "force"
        ;;
    help|-h|--help)
        show_usage
        ;;
    *)
        build
        ;;
esac
