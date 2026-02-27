#!/bin/bash
set -e

REPEATS="${1:-10000}"
HOST="${2:-host.docker.internal}"
PORT="${3:-56000}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$SCRIPT_DIR/results"
RESULT_FILE="$RESULTS_DIR/quic-ping-client_$(date +%Y%m%d_%H%M%S).txt"

mkdir -p "$RESULTS_DIR"
exec > >(tee -a "$RESULT_FILE")

if ! docker info >/dev/null 2>&1; then
  echo "Error: Docker daemon is not running"
  exit 1
fi

python3 "$PROJECT_DIR/test-data/mock_udp.py" >/tmp/mock_udp.log 2>&1 &
UDP_PID=$!
trap 'kill $UDP_PID >/dev/null 2>&1 || true' EXIT
sleep 1

echo "╔══════════════════════════════════════════╗"
echo "║         QUIC Ping Client Benchmark       ║"
echo "╚══════════════════════════════════════════╝"
echo "  Target   : ${HOST}:${PORT}"
echo "  Repeats  : $REPEATS"
echo "  Mode     : Docker"
echo ""

echo "── Building ──────────────────────────────────"
build_image() {
  local tag="$1" ctx="$2"
  printf "  [%-8s] " "$tag"
  if docker build -q -t "$tag" "$ctx" >/dev/null 2>&1; then echo "✓ $tag"; else echo "✗ build failed"; exit 1; fi
}
build_image "quic-go" "$PROJECT_DIR/go"
build_image "quic-rust" "$PROJECT_DIR/rust"
build_image "quic-zig" "$PROJECT_DIR/zig"
echo ""

RUNS=5
WARMUP=1
run_benchmark() {
  local name="$1" image="$2"
  printf "── %-4s ───────────────────────────────────────\n" "$name"
  local times=() min="" max="" total_processed="" avg_latency="" throughput="" processing_time=""

  for i in $(seq 1 $RUNS); do
    local output
    output=$(docker run --rm "$image" "$HOST" "$PORT" "$REPEATS" 2>&1)
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

run_benchmark "Go" "quic-go"
run_benchmark "Rust" "quic-rust"
run_benchmark "Zig" "quic-zig"

get_binary_size() {
  local image="$1" binary="$2" cid size
  cid=$(docker create "$image" 2>/dev/null) || { echo "N/A"; return; }
  size=$(docker cp "$cid:$binary" - 2>/dev/null | wc -c)
  docker rm "$cid" >/dev/null 2>&1
  awk -v b="$size" 'BEGIN { if (b >= 1048576) printf "%.1fMB", b/1048576; else printf "%dKB", b/1024 }'
}

echo "── Binary Size ───────────────────────────────"
printf "  Go  : %s\n" "$(get_binary_size quic-go /usr/local/bin/quic-ping-client)"
printf "  Rust: %s\n" "$(get_binary_size quic-rust /usr/local/bin/quic-ping-client)"
printf "  Zig : %s\n" "$(get_binary_size quic-zig /usr/local/bin/quic-ping-client)"
echo ""

echo "── Code Lines ────────────────────────────────"
wc -l < "$PROJECT_DIR/go/main.go" | awk '{printf "  Go  : %s lines\n", $1}'
wc -l < "$PROJECT_DIR/rust/src/main.rs" | awk '{printf "  Rust: %s lines\n", $1}'
wc -l < "$PROJECT_DIR/zig/src/main.zig" | awk '{printf "  Zig : %s lines\n", $1}'
echo ""

echo "── Results saved to ──────────────────────────"
echo "  $RESULT_FILE"
