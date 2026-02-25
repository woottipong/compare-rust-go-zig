#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEST_DATA_DIR="$PROJECT_DIR/test-data"
INPUT_FILE="test.json"
RESULT_DIR="$SCRIPT_DIR/results"

# Create results directory
mkdir -p "$RESULT_DIR"

# Generate timestamp for result file
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_FILE="$RESULT_DIR/vdi_${TIMESTAMP}.txt"

# Log to both console and file
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

echo "Building Go image..."
docker build -q -t vdi-go "$PROJECT_DIR/go"

echo "Building Rust image..."
docker build -q -t vdi-rust "$PROJECT_DIR/rust"

echo "Building Zig image..."
docker build -q -t vdi-zig "$PROJECT_DIR/zig"

echo ""

# Benchmark function
benchmark() {
    local lang=$1
    local image=$2
    local name=$3
    
    echo "=== $name ==="
    
    # Run benchmark (5 runs: 1 warmup + 4 measured)
    local times=()
    
    for i in 1 2 3 4 5; do
        echo "Run $i..."
        
        # Run container and capture output
        output=$(docker run --rm -v "$TEST_DATA_DIR":/data:ro "$image" "/data/$INPUT_FILE" 2>&1)
        
        # For warmup, skip
        if [ $i -eq 1 ]; then
            echo "  (warmup)"
            continue
        fi
        
        # Parse processing time from output
        proc_time=$(echo "$output" | grep "Processing time:" | awk -F': ' '{print $2}' | sed 's/s//')
        
        if [ -n "$proc_time" ]; then
            times+=("$proc_time")
            echo "  Processing time: ${proc_time}s"
        else
            echo "  Failed to parse output:"
            echo "$output"
        fi
    done
    
    # Calculate average
    if [ ${#times[@]} -gt 0 ]; then
        local sum=0
        for t in "${times[@]}"; do
            sum=$(echo "$sum + $t" | bc -l)
        done
        local avg=$(echo "scale=3; $sum / ${#times[@]}" | bc -l)
        
        # Find min and max
        local min="${times[0]}"
        local max="${times[0]}"
        for t in "${times[@]}"; do
            local less=$(echo "$t < $min" | bc -l)
            if [ "$less" -eq 1 ]; then
                min=$t
            fi
            local greater=$(echo "$t > $max" | bc -l)
            if [ "$greater" -eq 1 ]; then
                max=$t
            fi
        done
        
        echo ""
        echo "Results (excluding warmup):"
        echo "  Avg: ${avg}s"
        echo "  Min: ${min}s"
        echo "  Max: ${max}s"
        echo ""
    fi
    
    # Measure binary size
    cid=$(docker create "$image")
    if [ "$lang" = "zig" ]; then
        # Zig is built in place
        size=$(docker cp "$cid":/app/zig-0.15.2 - 2>/dev/null | wc -c || echo "0")
    else
        bin_name="vdi-$lang"
        size=$(docker cp "$cid":/usr/local/bin/$bin_name - 2>/dev/null | wc -c || echo "0")
    fi
    docker rm "$cid" > /dev/null 2>&1
    
    if [ "$size" -gt 0 ]; then
        size_kb=$((size / 1024))
        echo "Binary size: ${size_kb} KB"
    fi
    echo ""
}

# Run benchmarks
benchmark "go" "vdi-go" "Go"
benchmark "rust" "vdi-rust" "Rust"
benchmark "zig" "vdi-zig" "Zig"

echo "=== Benchmark Complete ==="
echo "Results saved to: $RESULT_FILE"
