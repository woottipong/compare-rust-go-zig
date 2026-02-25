#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$SCRIPT_DIR/results"
RESULT_FILE="$RESULTS_DIR/vdi_$(date +%Y%m%d_%H%M%S).txt"

mkdir -p "$RESULTS_DIR"
exec > >(tee -a "$RESULT_FILE") 2>&1

echo "=== Vector DB Ingester Benchmark ==="
echo "Date: $(date)"
echo ""

# Check Docker daemon
if ! docker info > /dev/null 2>&1; then
    echo "Error: Docker daemon is not running"
    exit 1
fi

# Build images
echo "Building Docker images..."
docker build -q -t vdi-go "$PROJECT_DIR/go"
docker build -q -t vdi-rust "$PROJECT_DIR/rust"
docker build -q -t vdi-zig "$PROJECT_DIR/zig"
echo ""

TEST_DATA_DIR="$PROJECT_DIR/test-data"
INPUT_FILE="medium-test.json"  # Use larger test data

# Benchmark function
run_benchmark() {
    local name="$1"
    local image="$2"
    
    echo "=== $name ==="
    
    # Run container with proper flags
    local output
    case "$name" in
        "Go")
            output=$(docker run --rm -v "$TEST_DATA_DIR":/data:ro "$image" -input "/data/$INPUT_FILE" 2>&1)
            ;;
        "Rust")
            output=$(docker run --rm -v "$TEST_DATA_DIR":/data:ro "$image" --input "/data/$INPUT_FILE" 2>&1)
            ;;
        "Zig")
            output=$(docker run --rm -v "$TEST_DATA_DIR":/data:ro "$image" "/data/$INPUT_FILE" 2>&1)
            ;;
    esac
    
    # Show output
    echo "$output"
    echo ""
}

run_benchmark "Go" "vdi-go"
run_benchmark "Rust" "vdi-rust"
run_benchmark "Zig" "vdi-zig"

echo "=== Benchmark Complete ==="
echo "Results saved to: $RESULT_FILE"
