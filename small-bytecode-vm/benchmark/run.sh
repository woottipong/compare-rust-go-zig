#!/bin/bash

set -euo pipefail
export LC_ALL=C

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
RESULT_FILE="$SCRIPT_DIR/results/small_bytecode_vm_$(date +%Y%m%d_%H%M%S).txt"

mkdir -p "$SCRIPT_DIR/results"
exec > >(tee -a "$RESULT_FILE")

echo "╔════════════════════════════╗"
echo "║ Small Bytecode VM Bench    ║"
echo "╚════════════════════════════╝"
echo

if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker daemon not running"
    exit 1
fi

echo "Building Docker images..."
echo

echo -n "Go:   "
if docker build -q -t bvm-go "$PROJECT_DIR/go/" >/dev/null 2>&1; then
    echo "✓"
else
    echo "✗ build failed"
    exit 1
fi

echo -n "Rust: "
if docker build -q -t bvm-rust "$PROJECT_DIR/rust/" >/dev/null 2>&1; then
    echo "✓"
else
    echo "✗ build failed"
    exit 1
fi

echo -n "Zig:  "
if docker build -q -t bvm-zig "$PROJECT_DIR/zig/" >/dev/null 2>&1; then
    echo "✓"
else
    echo "✗ build failed"
    exit 1
fi

echo
echo "Running benchmarks (5 runs each: 1 warm-up + 4 measured)..."
echo

PROGRAM="/data/loop_sum.bin"
ITERATIONS=1000000

for lang in Go Rust Zig; do
    image="bvm-$(echo "$lang" | tr '[:upper:]' '[:lower:]')"
    echo "─ $lang ─────────────────────"

    output=$(docker run --rm -v "$PROJECT_DIR/test-data:/data:ro" "$image" "$PROGRAM" "$ITERATIONS" 2>&1)
    warmup=$(echo "$output" | grep "Throughput:" | awk -F': ' '{print $2}' | awk '{print $1}')
    echo "  Warm-up: ${warmup} instructions/sec"

    total=0
    min=0
    max=0
    for i in {1..4}; do
        output=$(docker run --rm -v "$PROJECT_DIR/test-data:/data:ro" "$image" "$PROGRAM" "$ITERATIONS" 2>&1)
        throughput=$(echo "$output" | grep "Throughput:" | awk -F': ' '{print $2}' | awk '{print $1}')
        echo "  Run $i: ${throughput} instructions/sec"
        total=$(echo "$total + $throughput" | bc -l)

        int_tp=$(printf "%.0f" "$throughput")
        if [ "$min" -eq 0 ] || [ "$int_tp" -lt "$min" ]; then min=$int_tp; fi
        if [ "$int_tp" -gt "$max" ]; then max=$int_tp; fi
    done

    avg=$(echo "scale=2; $total / 4" | bc -l)
    echo "  Avg: ${avg} instructions/sec"
    echo "  Min: ${min} instructions/sec"
    echo "  Max: ${max} instructions/sec"
    echo
done

echo "─ Binary Size ───────────────"
for lang in Go Rust Zig; do
    image="bvm-$(echo "$lang" | tr '[:upper:]' '[:lower:]')"
    cid=$(docker create "$image")
    size=$(docker cp "$cid:/usr/local/bin/small-bytecode-vm" - | wc -c)
    docker rm "$cid" >/dev/null

    if [ "$size" -lt 1048576 ]; then
        size_fmt=$(echo "scale=2; $size / 1024" | bc -l)
        echo "  $lang: ${size_fmt}KB"
    else
        size_fmt=$(echo "scale=2; $size / 1048576" | bc -l)
        echo "  $lang: ${size_fmt}MB"
    fi
done

echo
echo "Benchmark completed. Results saved to: $RESULT_FILE"
