#!/bin/bash

# 🧹 Clean script for Compare Rust / Go / Zig repository
# Removes benchmark results, build artifacts, and optionally test data

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(dirname "$SCRIPT_DIR")

echo "🧹 Cleaning repository: $REPO_ROOT"
echo

# Function to count files before/after
count_files() {
    local pattern="$1"
    find "$REPO_ROOT" -path "$pattern" -type f 2>/dev/null | wc -l
}

# Count before cleaning
echo "📊 Before clean:"
RESULTS_BEFORE=$(count_files "*/benchmark/results/*.txt")
echo "  - Benchmark result files: $RESULTS_BEFORE"
ARTIFACTS_BEFORE=$(find "$REPO_ROOT" -name "target" -o -name "zig-out" -o -name "zig-cache" 2>/dev/null | wc -l)
echo "  - Build artifact directories: $ARTIFACTS_BEFORE"
BINARIES_BEFORE=$(find "$REPO_ROOT" -name "*.exe" -type f 2>/dev/null | wc -l)
echo "  - Binary files: $BINARIES_BEFORE"
echo

# Clean benchmark results
echo "🗑️  Cleaning benchmark results..."
RESULTS_DELETED=0
while IFS= read -r -d '' file; do
    echo "  - Removing: ${file#$REPO_ROOT/}"
    rm "$file"
    ((RESULTS_DELETED++))
done < <(find "$REPO_ROOT" -path "*/benchmark/results/*.txt" -type f -print0 2>/dev/null)
echo "  ✓ Deleted $RESULTS_DELETED benchmark result files"
echo

# Clean build artifacts
echo "🔨 Cleaning build artifacts..."
ARTIFACTS_DELETED=0
for dir in target zig-out zig-cache; do
    while IFS= read -r -d '' path; do
        echo "  - Removing directory: ${path#$REPO_ROOT/}"
        rm -rf "$path"
        ((ARTIFACTS_DELETED++))
    done < <(find "$REPO_ROOT" -name "$dir" -type d -print0 2>/dev/null)
done
echo "  ✓ Deleted $ARTIFACTS_DELETED build artifact directories"
echo

# Clean binary files
echo "📦 Cleaning binary files..."
BINARIES_DELETED=0
while IFS= read -r -d '' file; do
    echo "  - Removing: ${file#$REPO_ROOT/}"
    rm "$file"
    ((BINARIES_DELETED++))
done < <(find "$REPO_ROOT" -name "*.exe" -type f -print0 2>/dev/null)
echo "  ✓ Deleted $BINARIES_DELETED binary files"
echo

echo "ℹ️  Test data preserved (gitignored, safe to keep)"
echo

# Count after cleaning
echo "📊 After clean:"
RESULTS_AFTER=$(count_files "*/benchmark/results/*.txt")
echo "  - Benchmark result files: $RESULTS_AFTER"
ARTIFACTS_AFTER=$(find "$REPO_ROOT" -name "target" -o -name "zig-out" -o -name "zig-cache" 2>/dev/null | wc -l)
echo "  - Build artifact directories: $ARTIFACTS_AFTER"
BINARIES_AFTER=$(find "$REPO_ROOT" -name "*.exe" -type f 2>/dev/null | wc -l)
echo "  - Binary files: $BINARIES_AFTER"
echo

# Show repository size
echo "📏 Repository size:"
du -sh "$REPO_ROOT"
echo

echo "✅ Clean completed successfully!"
echo
echo "💡 Tips:"
echo "  - Test data is preserved for convenience"
echo "  - Use 'find . -name test-data -type d -exec rm -rf {} +' if you need to remove it"
echo "  - Use 'git status' to verify repository is clean"
