#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$SCRIPT_DIR/results"
RESULT_FILE="$RESULTS_DIR/vdi_$(date +%Y%m%d_%H%M%S).txt"

RUNS=5
WARMUP=1

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
    local times=()
    
    echo "=== $name ==="
    
    for i in $(seq 1 $RUNS); do
        local start end elapsed
        start=$(date +%s%N)
        
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
        
        end=$(date +%s%N)
        elapsed=$(( (end - start) / 1000000 ))
        
        if [ "$i" -le "$WARMUP" ]; then
            echo "  Run $i (warm-up): ${elapsed}ms"
            echo "$output"
        else
            echo "  Run $i           : ${elapsed}ms"
            echo "$output"
            times+=("$elapsed")
        fi
        echo ""
    done
    
    # Calculate statistics
    if [ ${#times[@]} -gt 0 ]; then
        local total=0 min=${times[0]} max=${times[0]}
        for t in "${times[@]}"; do
            total=$((total + t))
            [ "$t" -lt "$min" ] && min=$t
            [ "$t" -gt "$max" ] && max=$t
        done
        echo "  ─────────────────────────────────────────"
        echo "  Avg: $((total / ${#times[@]}))ms | Min: ${min}ms | Max: ${max}ms"
        echo ""
    fi
}

# Get binary size
get_binary_size() {
    local name="$1"
    local image="$2"
    
    # Create container without running it
    local container_id
    container_id=$(docker create --name "${name}_size" "$image" 2>/dev/null)
    
    # Copy binary out
    local binary_name
    case "$name" in
        "Go") binary_name="vdi-go" ;;
        "Rust") binary_name="vdi-rust" ;;
        "Zig") binary_name="vdi-zig" ;;
    esac
    
    docker cp "${container_id}:/usr/local/bin/$binary_name" "/tmp/$binary_name" 2>/dev/null
    local size=$(ls -lh "/tmp/$binary_name" | awk '{print $5}')
    rm -f "/tmp/$binary_name"
    
    # Remove container
    docker rm "${name}_size" >/dev/null 2>&1
    
    echo "$size"
}

# Get code lines
get_code_lines() {
    local name="$1"
    local path="$2"
    
    case "$name" in
        "Go")
            wc -l "$path/main.go" | awk '{print $1}'
            ;;
        "Rust")
            wc -l "$path/src/main.rs" | awk '{print $1}'
            ;;
        "Zig")
            wc -l "$path/src/main.zig" | awk '{print $1}'
            ;;
    esac
}

run_benchmark "Go" "vdi-go"
run_benchmark "Rust" "vdi-rust"
run_benchmark "Zig" "vdi-zig"

echo "=== Binary Size ==="
go_size=$(get_binary_size "Go" "vdi-go")
rust_size=$(get_binary_size "Rust" "vdi-rust")
zig_size=$(get_binary_size "Zig" "vdi-zig")

echo "Go  : $go_size"
echo "Rust: $rust_size"
echo "Zig : $zig_size"
echo ""

echo "=== Code Lines ==="
go_lines=$(get_code_lines "Go" "$PROJECT_DIR/go")
rust_lines=$(get_code_lines "Rust" "$PROJECT_DIR/rust")
zig_lines=$(get_code_lines "Zig" "$PROJECT_DIR/zig")

echo "Go  : $go_lines lines"
echo "Rust: $rust_lines lines"
echo "Zig : $zig_lines lines"
echo ""

echo "=== Test Data ==="
if [ -f "$TEST_DATA_DIR/$INPUT_FILE" ]; then
    data_size=$(ls -lh "$TEST_DATA_DIR/$INPUT_FILE" | awk '{print $5}')
    echo "Input file: $INPUT_FILE"
    echo "Size: $data_size"
else
    echo "Input file: $INPUT_FILE (not found)"
fi

echo ""
echo "=== Benchmark Complete ==="
echo "Results saved to: $RESULT_FILE"
