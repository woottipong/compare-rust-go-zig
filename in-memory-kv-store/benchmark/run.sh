#!/bin/bash

set -euo pipefail

export LC_ALL=C

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
RESULT_FILE="$SCRIPT_DIR/results/in_memory_kv_store_$(date +%Y%m%d_%H%M%S).txt"

# Ensure results directory exists
mkdir -p "$SCRIPT_DIR/results"

# Auto-save output
exec > >(tee -a "$RESULT_FILE")

echo "╔════════════════════════════╗"
echo "║ In-Memory KV Store Bench   ║"
echo "╚════════════════════════════╝"
echo

# Check Docker daemon
if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker daemon not running"
    exit 1
fi

# Build images
echo "Building Docker images..."
echo

echo -n "Go:   "
if docker build -q -t ikvs-go "$PROJECT_DIR/go/" >/dev/null 2>&1; then
    echo "✓"
else
    echo "✗ build failed"
    exit 1
fi

echo -n "Rust: "
if docker build -q -t ikvs-rust "$PROJECT_DIR/rust/" >/dev/null 2>&1; then
    echo "✓"
else
    echo "✗ build failed"
    exit 1
fi

echo -n "Zig:  "
if docker build -q -t ikvs-zig "$PROJECT_DIR/zig/" >/dev/null 2>&1; then
    echo "✓"
else
    echo "✗ build failed"
    exit 1
fi

echo
echo "Running benchmarks (5 runs each: 1 warm-up + 4 measured)..."
echo

# Number of operations for benchmark
NUM_OPS=100000

# Run benchmarks
for lang in Go Rust Zig; do
    image="ikvs-$(echo "$lang" | tr '[:upper:]' '[:lower:]')"
    echo "─ $lang ─────────────────────"

    # Warm-up run
    if [ "$lang" = "Rust" ]; then
        output=$(docker run --rm "$image" --operations "$NUM_OPS" 2>&1)
    else
        output=$(docker run --rm "$image" "$NUM_OPS" 2>&1)
    fi
    warmup_throughput=$(echo "$output" | grep "Throughput:" | awk -F': ' '{print $2}' | awk '{print $1}')
    echo "  Warm-up: ${warmup_throughput} ops/sec"

    # Measured runs
    total_throughput=0
    for i in {1..4}; do
        if [ "$lang" = "Rust" ]; then
            output=$(docker run --rm "$image" --operations "$NUM_OPS" 2>&1)
        else
            output=$(docker run --rm "$image" "$NUM_OPS" 2>&1)
        fi
        throughput=$(echo "$output" | grep "Throughput:" | awk -F': ' '{print $2}' | awk '{print $1}')
        echo "  Run $i: ${throughput} ops/sec"
        total_throughput=$(echo "$total_throughput + $throughput" | bc -l)
    done

    avg_throughput=$(echo "scale=0; $total_throughput / 4" | bc -l)
    echo "  Avg: ${avg_throughput} ops/sec"
    echo
done

# Binary sizes
echo "─ Binary Size ───────────────"
for lang in Go Rust Zig; do
    image="ikvs-$(echo "$lang" | tr '[:upper:]' '[:lower:]')"
    cid=$(docker create "$image")
    size=$(docker cp "$cid:/usr/local/bin/in-memory-kv-store" - | wc -c)
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
