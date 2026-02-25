#!/bin/bash
# Benchmark script for Custom Log Masker
# Usage: bash benchmark/run.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$SCRIPT_DIR/results"
RESULT_FILE="$RESULTS_DIR/custom-log-masker_$(date +%Y%m%d_%H%M%S).txt"

mkdir -p "$RESULTS_DIR"
exec > >(tee -a "$RESULT_FILE")

echo "╔══════════════════════════════════════════╗"
echo "║     Custom Log Masker Benchmark          ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# Check if test data exists, generate if not
if [ ! -f "$PROJECT_DIR/test-data/sample.log" ]; then
    echo "Generating test data..."
    mkdir -p "$PROJECT_DIR/test-data"
    cat > "$PROJECT_DIR/test-data/sample.log" << 'EOF'
2024-01-15 10:23:45 INFO User john.doe@example.com logged in from 192.168.1.100
2024-01-15 10:23:46 DEBUG API call with api_key=sk-1234567890abcdef1234567890abcdef
2024-01-15 10:23:47 ERROR Database connection failed for user jane.smith@company.co.th
2024-01-15 10:23:48 INFO Phone contact updated: +1 (555) 123-4567
2024-01-15 10:23:49 WARN Password reset requested for user bob.wilson@domain.com
2024-01-15 10:23:50 INFO Credit card ending in 4532015112830366 processed successfully
2024-01-15 10:23:51 DEBUG Token: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0
2024-01-15 10:23:52 INFO Social security number 123-45-6789 verified
2024-01-15 10:23:53 ERROR Login failed for user alice@example.org from IP 10.0.0.50
2024-01-15 10:23:54 INFO URL accessed: https://api.example.com/login?password=secret123&user=admin
2024-01-15 10:23:55 DEBUG Secret key: abcd1234efgh5678ijkl9012mnop3456qrst
2024-01-15 10:23:56 INFO Contact phone (66) 1234-5678 added to profile
2024-01-15 10:23:57 WARN Suspicious activity from 172.16.0.25
2024-01-15 10:23:58 INFO API key=prod_9876543210abcdef configured
2024-01-15 10:23:59 ERROR Payment failed for card 5555555555554444
EOF
    # Duplicate to create larger file
    for i in {1..6666}; do
        cat "$PROJECT_DIR/test-data/sample.log" >> "$PROJECT_DIR/test-data/large.log"
    done
    echo "Created sample.log (15 lines) and large.log (~100K lines)"
fi

INPUT_FILE="$PROJECT_DIR/test-data/large.log"
INPUT_LINES=$(wc -l < "$INPUT_FILE")
INPUT_SIZE=$(stat -f%z "$INPUT_FILE" 2>/dev/null || stat -c%s "$INPUT_FILE")
INPUT_SIZE_MB=$(awk -v b="$INPUT_SIZE" 'BEGIN { printf "%.1f", b/1048576 }')

echo "── Test Data ──────────────────────────────────"
echo "  Input file: test-data/large.log"
echo "  Lines: $INPUT_LINES"
echo "  Size: ${INPUT_SIZE_MB}MB"
echo ""

# Build images
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
build_image "clm-go"   "$PROJECT_DIR/go"
build_image "clm-rust" "$PROJECT_DIR/rust"
build_image "clm-zig"  "$PROJECT_DIR/zig"
echo ""

# Benchmark function (5 runs: 1 warm-up + 4 measured)
RUNS=5
WARMUP=1

run_benchmark() {
    local name="$1" image="$2"

    printf "── %-4s ───────────────────────────────────────\n" "$name"

    local times=() min="" max=""
    local lines="" matches="" throughput="" lines_per_sec=""

    for i in $(seq 1 $RUNS); do
        local output
        output=$(docker run --rm -v "$INPUT_FILE:/data/input.log:ro" "$image" \
            --input /data/input.log --output /dev/null 2>&1)

        if [ -z "$(echo "$output" | grep "Lines processed:")" ]; then
            echo "  FAILED (run $i) — output:"
            echo "$output"
            echo ""
            return
        fi

        local time_raw elapsed_ms
        time_raw=$(echo "$output" | grep "Processing time:" | awk '{print $3}')
        elapsed_ms=$(awk -v t="$time_raw" 'BEGIN { printf "%d", t * 1000 }')

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
            lines=$(echo "$output"        | grep "Lines processed:" | awk '{print $3}')
            matches=$(echo "$output"      | grep "Matches found:"   | awk '{print $3}')
            throughput=$(echo "$output"   | grep "Throughput:"      | awk '{print $2}')
            lines_per_sec=$(echo "$output" | grep "Lines/sec:"      | awk '{print $2}')
        fi
    done

    local total=0
    for t in "${times[@]}"; do total=$((total + t)); done
    local avg=$((total / ${#times[@]}))

    echo "  ─────────────────────────────────────────"
    printf "  Avg: %dms  |  Min: %dms  |  Max: %dms\n" "$avg" "$min" "$max"
    echo ""
    printf "  Lines processed : %s\n"  "$lines"
    printf "  Matches found   : %s\n"  "$matches"
    printf "  Throughput      : %s MB/s\n" "$throughput"
    printf "  Lines/sec       : %s\n"  "$lines_per_sec"
    echo ""
}

# Run benchmarks
run_benchmark "Go"   "clm-go"
run_benchmark "Rust" "clm-rust"
run_benchmark "Zig"  "clm-zig"

# Binary Size
echo "── Binary Size ───────────────────────────────"
get_binary_size() {
    local image="$1" binary="$2"
    local cid
    cid=$(docker create "$image" 2>/dev/null) || { echo "N/A"; return; }
    local size
    size=$(docker cp "$cid:$binary" - 2>/dev/null | wc -c)
    docker rm "$cid" >/dev/null 2>&1
    awk -v b="$size" 'BEGIN { if (b >= 1048576) printf "%.1fMB", b/1048576; else printf "%dKB", b/1024 }'
}

echo "  Go  : $(get_binary_size clm-go   /usr/local/bin/clm-go)"
echo "  Rust: $(get_binary_size clm-rust /usr/local/bin/clm-rust)"
echo "  Zig : $(get_binary_size clm-zig  /usr/local/bin/clm-zig)"
echo ""

# Code Lines
echo "── Code Lines ────────────────────────────────"
wc -l < "$PROJECT_DIR/go/main.go"       | awk '{printf "  Go  : %s lines\n", $1}'
wc -l < "$PROJECT_DIR/rust/src/main.rs" | awk '{printf "  Rust: %s lines\n", $1}'
wc -l < "$PROJECT_DIR/zig/src/main.zig" | awk '{printf "  Zig : %s lines\n", $1}'
echo ""

echo "── Results saved to ──────────────────────────"
echo "  $RESULT_FILE"
