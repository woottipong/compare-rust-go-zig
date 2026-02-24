#!/bin/bash
# Benchmark script for Subtitle Burn-in Engine
# Usage: ./benchmark/run.sh [input_video] [subtitle_file]
# Run from: subtitle-burn-in-engine/ directory

INPUT_VIDEO="${1:-test-data/video.mp4}"
SUBTITLE_FILE="${2:-test-data/subs.srt}"
RUNS=5         # จำนวนรอบ (รอบแรกถือเป็น warm-up)
WARMUP=1       # จำนวน warm-up runs ที่ไม่นับ average

if [ ! -f "$INPUT_VIDEO" ]; then
    echo "Error: Input video not found: $INPUT_VIDEO"
    echo "Tip: ffmpeg -f lavfi -i testsrc=duration=30:size=640x360:rate=25 -pix_fmt yuv420p test-data/video.mp4"
    exit 1
fi

if [ ! -f "$SUBTITLE_FILE" ]; then
    echo "Error: Subtitle file not found: $SUBTITLE_FILE"
    echo "Tip: Create test-data/subs.srt with SRT format"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "╔══════════════════════════════════════════╗"
echo "║    Subtitle Burn-in Engine Benchmark      ║"
echo "╚══════════════════════════════════════════╝"
echo "  Input    : $INPUT_VIDEO"
echo "  Subtitle : $SUBTITLE_FILE"
echo "  Runs     : ${RUNS} (${WARMUP} warm-up)"
echo ""

# ─── Build ────────────────────────────────────────────────────────────────────
echo "── Building ──────────────────────────────────"

echo "[Go]"
(unset GOROOT && cd "$PROJECT_DIR/go" && go build -o ../bin/burner-go . 2>&1) \
    && echo "  ✓ bin/burner-go" || echo "  ✗ build failed"

echo "[Rust]"
(cd "$PROJECT_DIR/rust" && \
  LLVM_CONFIG_PATH=/opt/homebrew/opt/llvm/bin/llvm-config \
  LIBCLANG_PATH=/opt/homebrew/opt/llvm/lib \
  PKG_CONFIG_PATH=/opt/homebrew/Cellar/ffmpeg/8.0.1_4/lib/pkgconfig \
  cargo build --release 2>&1 | grep -E "^error|Finished|Compiling sub") \
    && echo "  ✓ rust/target/release/subtitle-burn-in-engine" || echo "  ✗ build failed"

echo "[Zig]"
(cd "$PROJECT_DIR/zig" && zig build -Doptimize=ReleaseFast 2>&1) \
    && echo "  ✓ zig/zig-out/bin/subtitle-burn-in-engine" || echo "  ✗ build failed"

echo ""

# ─── Benchmark function ───────────────────────────────────────────────────────
run_benchmark() {
    local name="$1"
    local cmd="$2"
    local times=()
    local mem_kb=0
    local success=0

    printf "── %-6s ─────────────────────────────────────\n" "$name"

    for i in $(seq 1 $RUNS); do
        local output="/tmp/burn_${name}_$$.mp4"
        local start end elapsed

        start=$(date +%s%N)
        if /usr/bin/time -l $cmd "$INPUT_VIDEO" "$SUBTITLE_FILE" "$output" >/dev/null 2>/tmp/bench_time_$$.txt; then
            end=$(date +%s%N)
            elapsed=$(( (end - start) / 1000000 ))

            # Parse memory from /usr/bin/time -l output (macOS)
            local rss
            rss=$(grep "maximum resident set size" /tmp/bench_time_$$.txt 2>/dev/null | awk '{print $1}')
            if [ -n "$rss" ]; then
                mem_kb=$(( rss / 1024 ))
            fi

            # Check if output video was created
            if [ -f "$output" ]; then
                if [ "$i" -le "$WARMUP" ]; then
                    printf "  Run %d (warm-up): %dms\n" "$i" "$elapsed"
                else
                    printf "  Run %d           : %dms\n" "$i" "$elapsed"
                    times+=("$elapsed")
                    success=$((success + 1))
                fi
                rm -f "$output"
            else
                printf "  Run %d: FAILED (no output)\n" "$i"
            fi
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
[ -f "$PROJECT_DIR/bin/burner-go" ] && \
    run_benchmark "Go" "$PROJECT_DIR/bin/burner-go"

[ -f "$PROJECT_DIR/rust/target/release/subtitle-burn-in-engine" ] && \
    run_benchmark "Rust" "$PROJECT_DIR/rust/target/release/subtitle-burn-in-engine"

[ -f "$PROJECT_DIR/zig/zig-out/bin/subtitle-burn-in-engine" ] && \
    run_benchmark "Zig" "$PROJECT_DIR/zig/zig-out/bin/subtitle-burn-in-engine"

# ─── Binary Size ──────────────────────────────────────────────────────────────
echo "── Binary Size ───────────────────────────────"
[ -f "$PROJECT_DIR/bin/burner-go" ] && \
    ls -lh "$PROJECT_DIR/bin/burner-go" | awk '{printf "  Go  : %s\n", $5}'
[ -f "$PROJECT_DIR/rust/target/release/subtitle-burn-in-engine" ] && \
    ls -lh "$PROJECT_DIR/rust/target/release/subtitle-burn-in-engine" | awk '{printf "  Rust: %s\n", $5}'
[ -f "$PROJECT_DIR/zig/zig-out/bin/subtitle-burn-in-engine" ] && \
    ls -lh "$PROJECT_DIR/zig/zig-out/bin/subtitle-burn-in-engine" | awk '{printf "  Zig : %s\n", $5}'

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
