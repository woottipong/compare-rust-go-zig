#!/bin/bash
set -euo pipefail

INPUT_FILE="${1:-test-data/records.jsonl}"
REPEATS="${2:-3}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$SCRIPT_DIR/results"
RESULT_FILE="$RESULTS_DIR/json-transform-pipeline_$(date +%Y%m%d_%H%M%S).txt"

mkdir -p "$RESULTS_DIR"
exec > >(tee -a "$RESULT_FILE") 2>&1

echo "=== JSON Transform Pipeline Benchmark ==="
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
docker build -q -t jtp-go   "$PROJECT_DIR/go"   >/dev/null
docker build -q -t jtp-rust "$PROJECT_DIR/rust"  >/dev/null
docker build -q -t jtp-zig  "$PROJECT_DIR/zig"   >/dev/null
echo "Build complete."
echo ""

RUNS=5
WARMUP=1

run_benchmark() {
    local name="$1"
    local image="$2"
    local times=()

    echo "--- $name ---"
    for i in $(seq 1 $RUNS); do
        local output
        output=$(docker run --rm \
            -v "$INPUT_DIR":/data:ro \
            "$image" "/data/$INPUT_FNAME" "$REPEATS" 2>&1)

        local throughput
        throughput=$(echo "$output" | grep "Throughput:" | awk -F': ' '{print $2}' | awk '{print $1}')
        local proc_time
        proc_time=$(echo "$output" | grep "Processing time:" | awk -F': ' '{print $2}' | tr -d 's')

        if [ "$i" -le "$WARMUP" ]; then
            echo "  Run $i (warm-up): ${proc_time}s | ${throughput} items/sec"
        else
            echo "  Run $i: ${proc_time}s | ${throughput} items/sec"
            times+=("$throughput")
        fi
    done

    # Calculate avg/min/max from measured runs
    local sum=0 min="" max=""
    for t in "${times[@]}"; do
        sum=$(awk -v s="$sum" -v v="$t" 'BEGIN { printf "%.2f", s + v }')
        if [ -z "$min" ] || awk -v v="$t" -v m="$min" 'BEGIN { exit !(v < m) }'; then min="$t"; fi
        if [ -z "$max" ] || awk -v v="$t" -v m="$max" 'BEGIN { exit !(v > m) }'; then max="$t"; fi
    done
    local count="${#times[@]}"
    local avg
    avg=$(awk -v s="$sum" -v c="$count" 'BEGIN { printf "%.2f", s / c }')

    echo ""
    echo "  Avg: $avg items/sec | Min: $min | Max: $max"
    echo ""
}

run_benchmark "Go"   "jtp-go"
run_benchmark "Rust" "jtp-rust"
run_benchmark "Zig"  "jtp-zig"

echo "=== Results saved to: $RESULT_FILE ==="
