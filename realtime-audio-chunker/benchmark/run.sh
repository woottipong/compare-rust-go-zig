#!/bin/bash
# Benchmark script for Real-time Audio Chunker
# Usage: ./benchmark/run.sh [input_audio]
# Run from: realtime-audio-chunker/ directory

INPUT_AUDIO="${1:-test-data/sample.wav}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$SCRIPT_DIR/results"
RESULT_FILE="$RESULTS_DIR/realtime-audio-chunker_$(date +%Y%m%d_%H%M%S).txt"

mkdir -p "$RESULTS_DIR"
exec > >(tee -a "$RESULT_FILE")

if [ ! -f "$PROJECT_DIR/$INPUT_AUDIO" ] && [ ! -f "$INPUT_AUDIO" ]; then
    echo "Error: Input audio not found: $INPUT_AUDIO"
    echo "Tip: run ffmpeg command to generate test-data/sample.wav"
    exit 1
fi

INPUT_ABS="$(cd "$PROJECT_DIR" && realpath "$INPUT_AUDIO")"
INPUT_DIR="$(dirname "$INPUT_ABS")"
INPUT_FILE="$(basename "$INPUT_ABS")"

echo "╔══════════════════════════════════════════╗"
echo "║    Real-time Audio Chunker Benchmark     ║"
echo "╚══════════════════════════════════════════╝"
echo "  Input    : $INPUT_AUDIO"
echo "  Mode     : Docker (Simulated Real-time)"
echo ""

# ─── Build ────────────────────────────────────────────────────────────────────
echo "── Building ──────────────────────────────────"
build_image() {
    local tag="$1" ctx="$2"
    printf "  [%-8s] " "$tag"
    if docker build -q -t "$tag" "$ctx" >/dev/null 2>&1; then
        echo "✓ $tag"
    else
        echo "✗ build failed"
    fi
}
build_image "rac-go"   "$PROJECT_DIR/go"
build_image "rac-rust" "$PROJECT_DIR/rust"
build_image "rac-zig"  "$PROJECT_DIR/zig"
echo ""

# ─── Benchmark function (5 runs: 1 warm-up + 4 measured) ─────────────────────
RUNS=5
WARMUP=1

run_benchmark() {
    local name="$1" image="$2"

    printf "── %-4s ───────────────────────────────────────\n" "$name"

    local chunks="" avg_latency="" throughput=""
    local times=() min="" max=""

    for i in $(seq 1 $RUNS); do
        local output exit_code
        output=$(docker run --rm -v "$INPUT_DIR":/data:ro "$image" "/data/$INPUT_FILE" 2>&1)
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

        # capture stats from last measured run
        if [ "$i" -eq "$RUNS" ]; then
            chunks=$(echo "$output"      | grep "Total chunks:"    | awk -F': ' '{print $2}')
            avg_latency=$(echo "$output" | grep "Average latency:" | awk -F': ' '{print $2}')
            throughput=$(echo "$output"  | grep "Throughput:"      | awk -F': ' '{print $2}')
        fi
    done

    # calculate average
    local total=0
    for t in "${times[@]}"; do total=$((total + t)); done
    local avg=$((total / ${#times[@]}))

    echo "  ─────────────────────────────────────────"
    printf "  Avg: %dms  |  Min: %dms  |  Max: %dms\n" "$avg" "$min" "$max"
    echo ""
    printf "  Total Chunks : %s\n"  "$chunks"
    printf "  Avg Latency  : %s\n"  "$avg_latency"
    printf "  Throughput   : %s\n"  "$throughput"
    echo ""
}

# ─── Run benchmarks ───────────────────────────────────────────────────────────
run_benchmark "Go"   "rac-go"
run_benchmark "Rust" "rac-rust"
run_benchmark "Zig"  "rac-zig"

# ─── Binary Size ──────────────────────────────────────────────────────────────
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
printf "  Go  : %s\n" "$(get_binary_size rac-go   /usr/local/bin/realtime-audio-chunker-go)"
printf "  Rust: %s\n" "$(get_binary_size rac-rust /usr/local/bin/realtime-audio-chunker-rust)"
printf "  Zig : %s\n" "$(get_binary_size rac-zig  /usr/local/bin/realtime-audio-chunker-zig)"
echo ""

# ─── Code Lines ───────────────────────────────────────────────────────────────
echo "── Code Lines ────────────────────────────────"
wc -l < "$PROJECT_DIR/go/main.go"       | awk '{printf "  Go  : %s lines\n", $1}'
wc -l < "$PROJECT_DIR/rust/src/main.rs" | awk '{printf "  Rust: %s lines\n", $1}'
wc -l < "$PROJECT_DIR/zig/src/main.zig" | awk '{printf "  Zig : %s lines\n", $1}'
echo ""

echo "── Results saved to ──────────────────────────"
echo "  $RESULT_FILE"
