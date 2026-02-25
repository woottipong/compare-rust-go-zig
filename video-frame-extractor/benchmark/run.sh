#!/bin/bash
# Benchmark script for Video Frame Extractor
# Usage: ./benchmark/run.sh [input_video] [timestamp_sec]
# Run from: video-frame-extractor/ directory

INPUT_VIDEO="${1:-test-data/sample.mp4}"
TIMESTAMP="${2:-5.0}"
RUNS=5
WARMUP=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$SCRIPT_DIR/results"
RESULT_FILE="$RESULTS_DIR/video-frame-extractor_$(date +%Y%m%d_%H%M%S).txt"

mkdir -p "$RESULTS_DIR"
exec > >(tee -a "$RESULT_FILE")

if [ ! -f "$PROJECT_DIR/$INPUT_VIDEO" ] && [ ! -f "$INPUT_VIDEO" ]; then
    echo "Error: Input video not found: $INPUT_VIDEO"
    echo "Tip: ffmpeg -f lavfi -i testsrc=duration=30:size=1280x720:rate=30 -pix_fmt yuv420p test-data/sample.mp4"
    exit 1
fi

INPUT_ABS="$(cd "$PROJECT_DIR" && realpath "$INPUT_VIDEO")"
INPUT_DIR="$(dirname "$INPUT_ABS")"
INPUT_FILE="$(basename "$INPUT_ABS")"

echo "╔══════════════════════════════════════════╗"
echo "║    Video Frame Extractor Benchmark       ║"
echo "╚══════════════════════════════════════════╝"
echo "  Input    : $INPUT_VIDEO"
echo "  Timestamp: ${TIMESTAMP}s"
echo "  Runs     : ${RUNS} (${WARMUP} warm-up)"
echo "  Mode     : Docker"
echo ""

# ─── Build ────────────────────────────────────────────────────────────────────
echo "── Building ──────────────────────────────────"
build_image() {
    local tag="$1" ctx="$2"
    printf "  [%-8s] " "$tag"
    if docker build -t "$tag" "$ctx" >/dev/null 2>&1; then
        echo "✓ $tag"
    else
        echo "✗ build failed"
    fi
}
build_image "vfe-go"   "$PROJECT_DIR/go"
build_image "vfe-rust" "$PROJECT_DIR/rust"
build_image "vfe-zig"  "$PROJECT_DIR/zig"
echo ""

# ─── Benchmark function ───────────────────────────────────────────────────────
run_benchmark() {
    local name="$1" image="$2"
    local times=()

    printf "── %-4s ───────────────────────────────────────\n" "$name"

    for i in $(seq 1 $RUNS); do
        local start end elapsed
        start=$(date +%s%N)
        if docker run --rm \
            -v "$INPUT_DIR":/data:ro \
            -v /tmp:/out \
            "$image" "/data/$INPUT_FILE" "$TIMESTAMP" "/out/vfe_bench_$$.ppm" \
            >/dev/null 2>&1; then
            end=$(date +%s%N)
            elapsed=$(( (end - start) / 1000000 ))
            rm -f "/tmp/vfe_bench_$$.ppm"
            if [ "$i" -le "$WARMUP" ]; then
                printf "  Run %d (warm-up): %dms\n" "$i" "$elapsed"
            else
                printf "  Run %d           : %dms\n" "$i" "$elapsed"
                times+=("$elapsed")
            fi
        else
            printf "  Run %d: FAILED\n" "$i"
        fi
    done

    if [ ${#times[@]} -gt 0 ]; then
        local total=0 min=${times[0]} max=${times[0]}
        for t in "${times[@]}"; do
            total=$((total + t))
            [ "$t" -lt "$min" ] && min=$t
            [ "$t" -gt "$max" ] && max=$t
        done
        printf "  ─────────────────────────────────────────\n"
        printf "  Avg: %dms  |  Min: %dms  |  Max: %dms\n" "$((total / ${#times[@]}))" "$min" "$max"
    fi
    echo ""
}

# ─── Run benchmarks ───────────────────────────────────────────────────────────
run_benchmark "Go"   "vfe-go"
run_benchmark "Rust" "vfe-rust"
run_benchmark "Zig"  "vfe-zig"

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
printf "  Go  : %s\n" "$(get_binary_size vfe-go   /usr/local/bin/extractor-go)"
printf "  Rust: %s\n" "$(get_binary_size vfe-rust  /usr/local/bin/extractor-rust)"
printf "  Zig : %s\n" "$(get_binary_size vfe-zig   /usr/local/bin/extractor-zig)"
echo ""

# ─── Code Lines ───────────────────────────────────────────────────────────────
echo "── Code Lines ────────────────────────────────"
wc -l < "$PROJECT_DIR/go/main.go"       | awk '{printf "  Go  : %s lines\n", $1}'
wc -l < "$PROJECT_DIR/rust/src/main.rs" | awk '{printf "  Rust: %s lines\n", $1}'
wc -l < "$PROJECT_DIR/zig/src/main.zig" | awk '{printf "  Zig : %s lines\n", $1}'
echo ""

echo "── Results saved to ──────────────────────────"
echo "  $RESULT_FILE"
