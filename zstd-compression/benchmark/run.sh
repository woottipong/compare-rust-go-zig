#!/bin/bash
set -euo pipefail

INPUT_FILE="${1:-test-data/logs.txt}"
REPEATS="${2:-3}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$SCRIPT_DIR/results"
RESULT_FILE="$RESULTS_DIR/zstd-compression_$(date +%Y%m%d_%H%M%S).txt"

mkdir -p "$RESULTS_DIR"
exec > >(tee -a "$RESULT_FILE") 2>&1

echo "=== ZStandard Compression Benchmark ==="
echo "Date: $(date)"
echo "Input: $INPUT_FILE"
echo "Repeats per run: $REPEATS"
echo ""

# Resolve input path
if [[ "$INPUT_FILE" = /* ]]; then
    INPUT_DIR="$(dirname "$INPUT_FILE")"
    INPUT_FNAME="$(basename "$INPUT_FILE")"
else
    INPUT_DIR="$(cd "$PROJECT_DIR/$(dirname "$INPUT_FILE")" && pwd)"
    INPUT_FNAME="$(basename "$INPUT_FILE")"
fi

# Build images
echo "Building Docker images..."
docker build -q -t zst-go   "$PROJECT_DIR/go"   >/dev/null
docker build -q -t zst-rust "$PROJECT_DIR/rust"  >/dev/null
docker build -q -t zst-zig  "$PROJECT_DIR/zig"   >/dev/null
echo "Build complete."
echo ""

RUNS=5
WARMUP=1

run_benchmark() {
    local name="$1"
    local image="$2"
    local compress_times=()
    local decompress_times=()

    echo "--- $name ---"
    for i in $(seq 1 $RUNS); do
        local output
        output=$(docker run --rm \
            -v "$INPUT_DIR":/data:ro \
            "$image" "/data/$INPUT_FNAME" "$REPEATS" 2>&1)

        local compress_speed
        compress_speed=$(echo "$output" | grep "Compress speed:" | awk -F': ' '{print $2}' | awk '{print $1}')
        local decompress_speed
        decompress_speed=$(echo "$output" | grep "Decompress speed:" | awk -F': ' '{print $2}' | awk '{print $1}')
        local ratio
        ratio=$(echo "$output" | grep "Compression ratio:" | awk -F': ' '{print $2}' | tr -d 'x')

        if [ "$i" -le "$WARMUP" ]; then
            echo "  Run $i (warm-up): compress ${compress_speed} MB/s | decompress ${decompress_speed} MB/s | ratio ${ratio}x"
        else
            echo "  Run $i: compress ${compress_speed} MB/s | decompress ${decompress_speed} MB/s | ratio ${ratio}x"
            compress_times+=("$compress_speed")
            decompress_times+=("$decompress_speed")
        fi
    done

    # Calculate avg compress speed
    local sum=0 min="" max=""
    for t in "${compress_times[@]}"; do
        sum=$(awk -v s="$sum" -v v="$t" 'BEGIN { printf "%.2f", s + v }')
        if [ -z "$min" ] || awk -v v="$t" -v m="$min" 'BEGIN { exit !(v < m) }'; then min="$t"; fi
        if [ -z "$max" ] || awk -v v="$t" -v m="$max" 'BEGIN { exit !(v > m) }'; then max="$t"; fi
    done
    local count="${#compress_times[@]}"
    local avg
    avg=$(awk -v s="$sum" -v c="$count" 'BEGIN { printf "%.2f", s / c }')

    echo ""
    echo "  Compress Avg: $avg MB/s | Min: $min | Max: $max"
    echo ""
}

run_benchmark "Go"   "zst-go"
run_benchmark "Rust" "zst-rust"
run_benchmark "Zig"  "zst-zig"

echo "=== Results saved to: $RESULT_FILE ==="
