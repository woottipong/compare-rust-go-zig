#!/bin/bash
# Benchmark script for Subtitle Burn-in Engine
# Usage: ./benchmark/run.sh [input_video] [subtitle_file]
# Run from: subtitle-burn-in-engine/ directory

INPUT_VIDEO="${1:-test-data/video.mp4}"
SUBTITLE_FILE="${2:-test-data/subs.srt}"
RUNS=5         # จำนวนรอบ (รอบแรกถือเป็น warm-up)
WARMUP=1       # จำนวน warm-up runs ที่ไม่นับ average

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ ! -f "$PROJECT_DIR/$INPUT_VIDEO" ] && [ ! -f "$INPUT_VIDEO" ]; then
    echo "Error: Input video not found: $INPUT_VIDEO"
    echo "Tip: ffmpeg -f lavfi -i testsrc=duration=30:size=640x360:rate=25 -pix_fmt yuv420p test-data/video.mp4"
    exit 1
fi

if [ ! -f "$PROJECT_DIR/$SUBTITLE_FILE" ] && [ ! -f "$SUBTITLE_FILE" ]; then
    echo "Error: Subtitle file not found: $SUBTITLE_FILE"
    echo "Tip: Create test-data/subs.srt with SRT format"
    exit 1
fi

INPUT_ABS="$(cd "$PROJECT_DIR" && realpath "$INPUT_VIDEO")"
SUB_ABS="$(cd "$PROJECT_DIR" && realpath "$SUBTITLE_FILE")"
DATA_DIR="$(dirname "$INPUT_ABS")"

echo "╔══════════════════════════════════════════╗"
echo "║    Subtitle Burn-in Engine Benchmark      ║"
echo "╚══════════════════════════════════════════╝"
echo "  Input    : $INPUT_VIDEO"
echo "  Subtitle : $SUBTITLE_FILE"
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
build_image "sbe-go"   "$PROJECT_DIR/go"
build_image "sbe-rust" "$PROJECT_DIR/rust"
build_image "sbe-zig"  "$PROJECT_DIR/zig"
echo ""

# ─── Benchmark function ───────────────────────────────────────────────────────
run_benchmark() {
    local name="$1" image="$2"
    local times=()

    printf "── %-4s ───────────────────────────────────────\n" "$name"

    for i in $(seq 1 $RUNS); do
        local out_file="/tmp/burn_${name}_$$.mp4"
        local start end elapsed
        start=$(date +%s%N)
        if docker run --rm \
            -v "$DATA_DIR":/data:ro \
            -v /tmp:/out \
            "$image" \
            "/data/$(basename "$INPUT_ABS")" \
            "/data/$(basename "$SUB_ABS")" \
            "/out/$(basename "$out_file")" \
            >/dev/null 2>&1; then
            end=$(date +%s%N)
            elapsed=$(( (end - start) / 1000000 ))
            rm -f "$out_file"
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
        local img_mb
        img_mb=$(docker image inspect "$image" --format='{{.Size}}' 2>/dev/null | awk '{printf "%.0f", $1/1024/1024}')
        printf "  ─────────────────────────────────────────\n"
        printf "  Avg: %dms  |  Min: %dms  |  Max: %dms\n" "$((total / ${#times[@]}))" "$min" "$max"
        printf "  Image Size: %sMB\n" "$img_mb"
    fi
    echo ""
}

# ─── Run benchmarks ───────────────────────────────────────────────────────────
run_benchmark "Go"   "sbe-go"
run_benchmark "Rust" "sbe-rust"
run_benchmark "Zig"  "sbe-zig"

# ─── Code Lines ───────────────────────────────────────────────────────────────
echo "── Code Lines ────────────────────────────────"
wc -l < "$PROJECT_DIR/go/main.go"       | awk '{printf "  Go  : %s lines\n", $1}'
wc -l < "$PROJECT_DIR/rust/src/main.rs" | awk '{printf "  Rust: %s lines\n", $1}'
wc -l < "$PROJECT_DIR/zig/src/main.zig" | awk '{printf "  Zig : %s lines\n", $1}'
echo ""
