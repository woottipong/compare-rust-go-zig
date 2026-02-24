#!/bin/bash
# Benchmark script for HLS Stream Segmenter
# Usage: ./benchmark/run.sh [input_video] [segment_duration_sec]
# Run from: hls-stream-segmenter/ directory

INPUT_VIDEO="${1:-test-data/sample.mp4}"
SEGMENT_DURATION="${2:-10}"
RUNS=5         # จำนวนรอบ (รอบแรกถือเป็น warm-up)
WARMUP=1       # จำนวน warm-up runs ที่ไม่นับ average

if [ ! -f "$INPUT_VIDEO" ]; then
    echo "Error: Input video not found: $INPUT_VIDEO"
    echo "Tip: ffmpeg -f lavfi -i testsrc=duration=30:size=1280x720:rate=30 -pix_fmt yuv420p test-data/sample.mp4"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "╔══════════════════════════════════════════╗"
echo "║      HLS Stream Segmenter Benchmark       ║"
echo "╚══════════════════════════════════════════╝"
echo "  Input    : $INPUT_VIDEO"
echo "  Segment  : ${SEGMENT_DURATION}s"
echo "  Runs     : ${RUNS} (${WARMUP} warm-up)"
echo ""

# ─── Build ────────────────────────────────────────────────────────────────────
echo "── Building ──────────────────────────────────"

echo "[Go]"
(unset GOROOT && cd "$PROJECT_DIR/go" && go mod init hls-stream-segmenter 2>/dev/null && go build -o ../bin/segmenter-go . 2>&1) \
    && echo "  ✓ bin/segmenter-go" || echo "  ✗ build failed"

echo "[Rust]"
(cd "$PROJECT_DIR/rust" && \
  LLVM_CONFIG_PATH=/opt/homebrew/opt/llvm/bin/llvm-config \
  LIBCLANG_PATH=/opt/homebrew/opt/llvm/lib \
  PKG_CONFIG_PATH=/opt/homebrew/Cellar/ffmpeg/8.0.1_4/lib/pkgconfig \
  cargo build --release 2>&1 | grep -E "^error|Finished|Compiling hls") \
    && echo "  ✓ rust/target/release/hls-stream-segmenter" || echo "  ✗ build failed"

echo "[Zig]"
(cd "$PROJECT_DIR/zig" && zig build -Doptimize=ReleaseFast 2>&1) \
    && echo "  ✓ zig/zig-out/bin/hls-stream-segmenter" || echo "  ✗ build failed"

echo ""

# ─── Benchmark function ───────────────────────────────────────────────────────
run_benchmark() {
    local name="$1"
    local cmd="$2"
    local times=()
    local mem_kb=0
    local success=0

    printf "── %-6s ─────────────────────────────────────\n" "$name"

    # Clean output directory before each run
    rm -rf "/tmp/hls_bench_$name" 2>/dev/null

    for i in $(seq 1 $RUNS); do
        local output_dir="/tmp/hls_bench_$name"
        local start end elapsed

        start=$(date +%s%N)
        if /usr/bin/time -l $cmd "$INPUT_VIDEO" "$output_dir" "$SEGMENT_DURATION" >/dev/null 2>/tmp/bench_time_$$.txt; then
            end=$(date +%s%N)
            elapsed=$(( (end - start) / 1000000 ))

            # Parse memory from /usr/bin/time -l output (macOS)
            local rss
            rss=$(grep "maximum resident set size" /tmp/bench_time_$$.txt 2>/dev/null | awk '{print $1}')
            if [ -n "$rss" ]; then
                mem_kb=$(( rss / 1024 ))
            fi

            # Check if segments were created
            local segment_count
            segment_count=$(find "$output_dir" -name "*.ts" 2>/dev/null | wc -l)

            if [ "$i" -le "$WARMUP" ]; then
                printf "  Run %d (warm-up): %dms (%d segments)\n" "$i" "$elapsed" "$segment_count"
            else
                printf "  Run %d           : %dms (%d segments)\n" "$i" "$elapsed" "$segment_count"
                times+=("$elapsed")
                success=$((success + 1))
            fi
            rm -rf "$output_dir"
        else
            printf "  Run %d: FAILED\n" "$i"
        fi
        rm -f /tmp/bench_time_$$.txt
    done

    if [ ${#times[@]} -gt 0 ]; then
        local total=0
        local min=${times[0]}
        local max=${times[0]}
        for t in "${times[@]}"; do
            total=$((total + t))
            [ "$t" -lt "$min" ] && min=$t
            [ "$t" -gt "$max" ] && max=$t
        done
        local avg=$((total / ${#times[@]}))
        printf "  ─────────────────────────────────────────\n"
        printf "  Avg: %dms  |  Min: %dms  |  Max: %dms\n" "$avg" "$min" "$max"
        [ "$mem_kb" -gt 0 ] && printf "  Peak Memory: %d KB\n" "$mem_kb"
    fi
    echo ""
}

# ─── Run benchmarks ───────────────────────────────────────────────────────────
[ -f "$PROJECT_DIR/bin/segmenter-go" ] && \
    run_benchmark "Go" "$PROJECT_DIR/bin/segmenter-go"

[ -f "$PROJECT_DIR/rust/target/release/hls-stream-segmenter" ] && \
    run_benchmark "Rust" "$PROJECT_DIR/rust/target/release/hls-stream-segmenter"

[ -f "$PROJECT_DIR/zig/zig-out/bin/hls-stream-segmenter" ] && \
    run_benchmark "Zig" "$PROJECT_DIR/zig/zig-out/bin/hls-stream-segmenter"

# ─── Binary Size ──────────────────────────────────────────────────────────────
echo "── Binary Size ───────────────────────────────"
[ -f "$PROJECT_DIR/bin/segmenter-go" ] && \
    ls -lh "$PROJECT_DIR/bin/segmenter-go" | awk '{printf "  Go  : %s\n", $5}'
[ -f "$PROJECT_DIR/rust/target/release/hls-stream-segmenter" ] && \
    ls -lh "$PROJECT_DIR/rust/target/release/hls-stream-segmenter" | awk '{printf "  Rust: %s\n", $5}'
[ -f "$PROJECT_DIR/zig/zig-out/bin/hls-stream-segmenter" ] && \
    ls -lh "$PROJECT_DIR/zig/zig-out/bin/hls-stream-segmenter" | awk '{printf "  Zig : %s\n", $5}'

# ─── Code Lines ───────────────────────────────────────────────────────────────
echo ""
echo "── Code Lines ────────────────────────────────"
[ -f "$PROJECT_DIR/go/main.go" ] && \
    wc -l < "$PROJECT_DIR/go/main.go" | awk '{printf "  Go  : %s lines\n", $1}'
[ -f "$PROJECT_DIR/rust/src/main.rs" ] && \
    wc -l < "$PROJECT_DIR/rust/src/main.rs" | awk '{printf "  Rust: %s lines\n", $1}'
[ -f "$PROJECT_DIR/zig/src/main.zig" ] && \
    wc -l < "$PROJECT_DIR/zig/src/main.zig" | awk '{printf "  Zig : %s lines\n", $1}'

echo ""
