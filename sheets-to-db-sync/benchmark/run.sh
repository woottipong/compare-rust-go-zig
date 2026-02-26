#!/bin/bash
set -e

REPEATS="${1:-200000}"
SHEET_FILE="${2:-sheet.csv}"
DB_FILE="${3:-db.csv}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
INPUT_DIR="$PROJECT_DIR/test-data"
RESULTS_DIR="$SCRIPT_DIR/results"
RESULT_FILE="$RESULTS_DIR/sheets-to-db-sync_$(date +%Y%m%d_%H%M%S).txt"

mkdir -p "$RESULTS_DIR"
exec > >(tee -a "$RESULT_FILE")

if ! docker info >/dev/null 2>&1; then
  echo "Error: Docker daemon is not running"
  exit 1
fi

echo "╔══════════════════════════════════════════╗"
echo "║         Sheets-to-DB Sync Bench          ║"
echo "╚══════════════════════════════════════════╝"
echo "  Input    : /data/${SHEET_FILE}, /data/${DB_FILE}"
echo "  Repeats  : ${REPEATS}"
echo "  Mode     : Docker"
echo ""

echo "── Building ──────────────────────────────────"
build_image() {
  local tag="$1" ctx="$2"
  printf "  [%-8s] " "$tag"
  if docker build -q -t "$tag" "$ctx" >/dev/null 2>&1; then echo "✓ $tag"; else echo "✗ build failed"; exit 1; fi
}
build_image "s2d-go" "$PROJECT_DIR/go"
build_image "s2d-rust" "$PROJECT_DIR/rust"
build_image "s2d-zig" "$PROJECT_DIR/zig"
echo ""

RUNS=5
WARMUP=1
run_benchmark() {
  local name="$1" image="$2"
  printf "── %-4s ───────────────────────────────────────\n" "$name"
  local times=() min="" max="" total_processed="" avg_latency="" throughput="" processing_time=""

  for i in $(seq 1 $RUNS); do
    local output
    output=$(docker run --rm -v "$INPUT_DIR":/data:ro "$image" "/data/${SHEET_FILE}" "/data/${DB_FILE}" "$REPEATS" 2>&1)
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

run_benchmark "Go" "s2d-go"
run_benchmark "Rust" "s2d-rust"
run_benchmark "Zig" "s2d-zig"

get_binary_size() {
  local image="$1" binary="$2" cid size
  cid=$(docker create "$image" 2>/dev/null) || { echo "N/A"; return; }
  size=$(docker cp "$cid:$binary" - 2>/dev/null | wc -c)
  docker rm "$cid" >/dev/null 2>&1
  awk -v b="$size" 'BEGIN { if (b >= 1048576) printf "%.1fMB", b/1048576; else printf "%dKB", b/1024 }'
}

echo "── Binary Size ───────────────────────────────"
printf "  Go  : %s\n" "$(get_binary_size s2d-go /usr/local/bin/sheets-to-db-sync)"
printf "  Rust: %s\n" "$(get_binary_size s2d-rust /usr/local/bin/sheets-to-db-sync)"
printf "  Zig : %s\n" "$(get_binary_size s2d-zig /usr/local/bin/sheets-to-db-sync)"
echo ""

echo "── Code Lines ────────────────────────────────"
wc -l < "$PROJECT_DIR/go/main.go" | awk '{printf "  Go  : %s lines\n", $1}'
wc -l < "$PROJECT_DIR/rust/src/main.rs" | awk '{printf "  Rust: %s lines\n", $1}'
wc -l < "$PROJECT_DIR/zig/src/main.zig" | awk '{printf "  Zig : %s lines\n", $1}'
echo ""

echo "── Results saved to ──────────────────────────"
echo "  $RESULT_FILE"
