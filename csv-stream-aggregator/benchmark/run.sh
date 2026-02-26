#!/bin/bash
# Benchmark script for CSV Stream Aggregator
# Usage: bash benchmark/run.sh [input_csv] [repeats]

set -e

INPUT_CSV="${1:-test-data/sales.csv}"
REPEATS="${2:-30}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$SCRIPT_DIR/results"
RESULT_FILE="$RESULTS_DIR/csv-stream-aggregator_$(date +%Y%m%d_%H%M%S).txt"

mkdir -p "$RESULTS_DIR"
exec > >(tee -a "$RESULT_FILE")

if ! docker info >/dev/null 2>&1; then
    echo "Error: Docker daemon is not running"
    exit 1
fi

if [ ! -f "$PROJECT_DIR/$INPUT_CSV" ] && [ ! -f "$INPUT_CSV" ]; then
    python3 "$PROJECT_DIR/test-data/generate.py"
fi

INPUT_ABS="$(cd "$PROJECT_DIR" && realpath "$INPUT_CSV")"
INPUT_DIR="$(dirname "$INPUT_ABS")"
INPUT_FILE="$(basename "$INPUT_ABS")"

echo "╔══════════════════════════════════════════╗"
echo "║      CSV Stream Aggregator Benchmark     ║"
echo "╚══════════════════════════════════════════╝"
echo "  Input    : $INPUT_CSV"
echo "  Repeats  : $REPEATS"
echo "  Mode     : Docker"
echo ""

echo "── Building ──────────────────────────────────"
build_image() {
    local tag="$1" ctx="$2"
    printf "  [%-8s] " "$tag"
    if docker build -q -t "$tag" "$ctx" >/dev/null 2>&1; then
        echo "✓ $tag"
    else
        echo "✗ build failed"
        exit 1
    fi
}
build_image "csa-go"   "$PROJECT_DIR/go"
build_image "csa-rust" "$PROJECT_DIR/rust"
build_image "csa-zig"  "$PROJECT_DIR/zig"
echo ""

RUNS=5
WARMUP=1

run_benchmark() {
    local name="$1" image="$2"

    printf "── %-4s ───────────────────────────────────────\n" "$name"

    local times=() min="" max=""
    local total_processed="" avg_latency="" throughput="" processing_time=""

    for i in $(seq 1 $RUNS); do
        local output exit_code
        output=$(docker run --rm -v "$INPUT_DIR":/data:ro "$image" "/data/$INPUT_FILE" "$REPEATS" 2>&1)
        exit_code=$?

        if [ $exit_code -ne 0 ]; then
            echo "  FAILED (run $i, exit $exit_code)"
            echo "$output"
            echo ""
            return
        fi

        local proc_time_raw
        proc_time_raw=$(echo "$output" | grep "Processing time:" | awk -F': ' '{print $2}' | tr -d 's')
        local elapsed_ms
        elapsed_ms=$(awk -v t="$proc_time_raw" 'BEGIN { printf "%d", t * 1000 }')

        if [ "$i" -le "$WARMUP" ]; then
            printf "  Run %d (warm-up): %dms\n" "$i" "$elapsed_ms"
        else
            printf "  Run %d           : %dms\n" "$i" "$elapsed_ms"
            times+=("$elapsed_ms")
            [ -z "$min" ] || [ "$elapsed_ms" -lt "$min" ] && min=$elapsed_ms
            [ -z "$max" ] || [ "$elapsed_ms" -gt "$max" ] && max=$elapsed_ms
        fi

        if [ "$i" -eq "$RUNS" ]; then
            total_processed=$(echo "$output" | grep "Total processed:" | awk -F': ' '{print $2}')
            processing_time=$(echo "$output" | grep "Processing time:" | awk -F': ' '{print $2}')
            avg_latency=$(echo "$output" | grep "Average latency:" | awk -F': ' '{print $2}')
            throughput=$(echo "$output" | grep "Throughput:" | awk -F': ' '{print $2}')
        fi
    done

    local total=0
    for t in "${times[@]}"; do total=$((total + t)); done
    local avg=$((total / ${#times[@]}))

    echo "  ─────────────────────────────────────────"
    printf "  Avg: %dms  |  Min: %dms  |  Max: %dms\n" "$avg" "$min" "$max"
    echo ""
    printf "  Total processed: %s\n" "$total_processed"
    printf "  Processing time: %s\n" "$processing_time"
    printf "  Average latency: %s\n" "$avg_latency"
    printf "  Throughput     : %s\n" "$throughput"
    echo ""
}

run_benchmark "Go"   "csa-go"
run_benchmark "Rust" "csa-rust"
run_benchmark "Zig"  "csa-zig"

get_binary_size() {
    local image="$1" binary="$2"
    local cid
    cid=$(docker create "$image" 2>/dev/null) || { echo "N/A"; return; }
    local size
    size=$(docker cp "$cid:$binary" - 2>/dev/null | wc -c)
    docker rm "$cid" >/dev/null 2>&1
    awk -v b="$size" 'BEGIN { if (b >= 1048576) printf "%.1fMB", b/1048576; else printf "%dKB", b/1024 }'
}

echo "── Binary Size ───────────────────────────────"
printf "  Go  : %s\n" "$(get_binary_size csa-go   /usr/local/bin/csv-stream-aggregator)"
printf "  Rust: %s\n" "$(get_binary_size csa-rust /usr/local/bin/csv-stream-aggregator)"
printf "  Zig : %s\n" "$(get_binary_size csa-zig  /usr/local/bin/csv-stream-aggregator)"
echo ""

echo "── Code Lines ────────────────────────────────"
wc -l < "$PROJECT_DIR/go/main.go"       | awk '{printf "  Go  : %s lines\n", $1}'
wc -l < "$PROJECT_DIR/rust/src/main.rs" | awk '{printf "  Rust: %s lines\n", $1}'
wc -l < "$PROJECT_DIR/zig/src/main.zig" | awk '{printf "  Zig : %s lines\n", $1}'
echo ""

echo "── Results saved to ──────────────────────────"
echo "  $RESULT_FILE"
