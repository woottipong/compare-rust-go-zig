#!/bin/bash
# Benchmark script for SQLite Query Engine
# Usage: bash benchmark/run.sh [input_db] [repeats]

set -e

INPUT_DB="${1:-test-data/metrics.db}"
REPEATS="${2:-1000}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$SCRIPT_DIR/results"
RESULT_FILE="$RESULTS_DIR/sqlite-query-engine_$(date +%Y%m%d_%H%M%S).txt"

mkdir -p "$RESULTS_DIR"
exec > >(tee -a "$RESULT_FILE")

if ! docker info >/dev/null 2>&1; then
    echo "Error: Docker daemon is not running"
    exit 1
fi

if [ ! -f "$PROJECT_DIR/$INPUT_DB" ] && [ ! -f "$INPUT_DB" ]; then
    echo "Error: Input database not found: $INPUT_DB"
    echo "Tip: run python3 test-data/generate.py"
    exit 1
fi

INPUT_ABS="$(cd "$PROJECT_DIR" && realpath "$INPUT_DB")"
INPUT_DIR="$(dirname "$INPUT_ABS")"
INPUT_FILE="$(basename "$INPUT_ABS")"

echo "╔══════════════════════════════════════════╗"
echo "║      SQLite Query Engine Benchmark       ║"
echo "╚══════════════════════════════════════════╝"
echo "  Input    : $INPUT_DB"
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
build_image "sqe-go"   "$PROJECT_DIR/go"
build_image "sqe-rust" "$PROJECT_DIR/rust"
build_image "sqe-zig"  "$PROJECT_DIR/zig"
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

run_benchmark "Go"   "sqe-go"
run_benchmark "Rust" "sqe-rust"
run_benchmark "Zig"  "sqe-zig"

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
printf "  Go  : %s\n" "$(get_binary_size sqe-go   /usr/local/bin/sqlite-query-engine)"
printf "  Rust: %s\n" "$(get_binary_size sqe-rust /usr/local/bin/sqlite-query-engine)"
printf "  Zig : %s\n" "$(get_binary_size sqe-zig  /usr/local/bin/sqlite-query-engine)"
echo ""

echo "── Code Lines ────────────────────────────────"
wc -l < "$PROJECT_DIR/go/main.go"       | awk '{printf "  Go  : %s lines\n", $1}'
wc -l < "$PROJECT_DIR/rust/src/main.rs" | awk '{printf "  Rust: %s lines\n", $1}'
wc -l < "$PROJECT_DIR/zig/src/main.zig" | awk '{printf "  Zig : %s lines\n", $1}'
echo ""

echo "── Results saved to ──────────────────────────"
echo "  $RESULT_FILE"
