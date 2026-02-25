#!/bin/bash
# Benchmark script for Log Aggregator Sidecar
# Usage: ./benchmark/run.sh
# Run from: log-aggregator-sidecar/ directory

set -e

RUNS=5         # จำนวนรอบ (รอบแรกถือเป็น warm-up)
WARMUP=1       # จำนวน warm-up runs ที่ไม่นับ average
TEST_FILE="test-data/app.log"
MOCK_PORT=9200
NETWORK_NAME="las-bench-net"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$SCRIPT_DIR/results"
mkdir -p "$RESULTS_DIR"
RESULT_FILE="$RESULTS_DIR/log-aggregator-sidecar_$(date +%Y%m%d_%H%M%S).txt"

# Tee all output to result file
exec > >(tee -a "$RESULT_FILE") 2>&1

echo "╔══════════════════════════════════════════╗"
echo "║     Log Aggregator Sidecar Benchmark     ║"
echo "╚══════════════════════════════════════════╝"
echo "  Test File: $TEST_FILE"
echo "  Mock Port : $MOCK_PORT"
echo "  Runs      : ${RUNS} (${WARMUP} warm-up)"
echo "  Mode      : Docker"
echo ""

# ─── Generate test data if needed ────────────────────────────────────────
if [ ! -f "$PROJECT_DIR/$TEST_FILE" ]; then
    echo "── Generating Test Data ───────────────────────"
    mkdir -p "$PROJECT_DIR/test-data"
    python3 -c "
import random, time, json, sys
levels = ['INFO', 'WARN', 'ERROR', 'DEBUG']
apps = ['auth', 'payment', 'api', 'worker']
for i in range(100000):
    level = random.choice(levels)
    app = random.choice(apps)
    ts = time.strftime('%Y-%m-%d %H:%M:%S', time.gmtime(time.time() - random.randint(0, 86400)))
    msg = f'User {random.randint(1000,9999)} {\"login\" if level==\"INFO\" else \"failed\"} from {random.randint(1,255)}.{random.randint(1,255)}.{random.randint(1,255)}.{random.randint(1,255)}'
    print(f'{ts} {level} {app}[{random.randint(1,10)}]: {msg}')
" > "$PROJECT_DIR/$TEST_FILE"
    echo "  ✓ Generated 100K lines in $TEST_FILE"
    echo ""
fi

# ─── Docker network ───────────────────────────────────────────────────────────
docker network create "$NETWORK_NAME" >/dev/null 2>&1 || true

# ─── Start Mock Backend ───────────────────────────────────────────────────────
echo "── Starting Mock Backend ────────────────────────"
cd "$PROJECT_DIR"

docker build -t las-mock-backend -f - test-data <<'DOCKEREOF' >/dev/null 2>&1
FROM golang:1.25-bookworm AS builder
WORKDIR /src
COPY . .
RUN mkdir -p /out && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /out/mock-backend mock_backend.go
FROM debian:bookworm-slim
COPY --from=builder /out/mock-backend /usr/local/bin/mock-backend
ENTRYPOINT ["mock-backend"]
CMD [":9200"]
DOCKEREOF

docker rm -f las-mock-backend >/dev/null 2>&1 || true
docker run -d --name las-mock-backend \
    --network "$NETWORK_NAME" \
    -p $MOCK_PORT:9200 \
    las-mock-backend ":9200" >/dev/null 2>&1
BACKEND_CONTAINER=las-mock-backend

sleep 2
if ! curl -s http://localhost:$MOCK_PORT/health >/dev/null 2>&1; then
    echo "  ✗ Backend failed to start"
    docker rm -f "$BACKEND_CONTAINER" 2>/dev/null
    docker network rm "$NETWORK_NAME" 2>/dev/null
    exit 1
fi
echo "  ✓ Backend running on port $MOCK_PORT (container: las-mock-backend)"

# ─── Build ────────────────────────────────────────────────────────────────────
echo ""
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
build_image "las-go"   "$PROJECT_DIR/go"
build_image "las-rust" "$PROJECT_DIR/rust"
build_image "las-zig"  "$PROJECT_DIR/zig"
echo ""

# ─── Binary size from Docker image ────────────────────────────────────────────
image_binary_size() {
    local image="$1" binary="$2"
    local cid tmp
    tmp=$(mktemp)
    cid=$(docker create "$image" 2>/dev/null)
    docker cp "${cid}:${binary}" "$tmp" >/dev/null 2>&1
    docker rm "$cid" >/dev/null 2>&1
    local size
    size=$(wc -c < "$tmp" 2>/dev/null | tr -d ' ')
    rm -f "$tmp"
    if [ -n "$size" ] && [ "$size" -gt 0 ] 2>/dev/null; then
        awk -v s="$size" 'BEGIN{printf "%.1fMB", s/1024/1024}'
    else
        echo "N/A"
    fi
}

# ─── Benchmark function ───────────────────────────────────────────────────────
run_benchmark() {
    local name="$1"
    local image="$2"
    local binary="$3"
    local lines_list=()
    local CONTAINER_NAME="las-bench-$$"

    printf "── %-6s ──────────────────────────────────────\n" "$name"

    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker run -d --name "$CONTAINER_NAME" \
        --network "$NETWORK_NAME" \
        -v "$PROJECT_DIR/test-data:/logs:ro" \
        "$image" \
        --input "/logs/app.log" \
        --output "http://las-mock-backend:9200" \
        --workers 4 \
        --buffer 1000 >/dev/null 2>&1
    
    # Wait for processing to complete
    sleep 3
    
    # Get stats from container
    local stats_json
    stats_json=$(docker exec "$CONTAINER_NAME" curl -s http://localhost:8080/stats 2>/dev/null || echo "{}")
    
    # Parse stats (simplified)
    local lines_processed
    lines_processed=$(echo "$stats_json" | grep -o '"total_processed":[0-9]*' | cut -d: -f2)
    if [ -z "$lines_processed" ]; then
        lines_processed=0
    fi
    
    local mem_kb
    mem_kb=$(docker stats --no-stream --format '{{.MemUsage}}' "$CONTAINER_NAME" 2>/dev/null | \
        awk '{gsub(/MiB/,""); printf "%.0f", $1*1024}')

    for i in $(seq 1 $RUNS); do
        # Simulate multiple runs by restarting the container
        docker restart "$CONTAINER_NAME" >/dev/null 2>&1
        sleep 2
        
        local current_lines
        current_lines=$(docker exec "$CONTAINER_NAME" curl -s http://localhost:8080/stats 2>/dev/null | \
            grep -o '"total_processed":[0-9]*' | cut -d: -f2)
        
        if [ -z "$current_lines" ]; then
            current_lines=0
        fi
        
        if [ "$i" -le "$WARMUP" ]; then
            printf "  Run %d (warm-up): %d lines\n" "$i" "$current_lines"
        else
            printf "  Run %d           : %d lines\n" "$i" "$current_lines"
            lines_list+=("$current_lines")
        fi
    done

    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
    sleep 1

    if [ ${#lines_list[@]} -gt 0 ]; then
        local total=0 min=${lines_list[0]} max=${lines_list[0]}
        for l in "${lines_list[@]}"; do
            total=$((total + l))
            [ "$l" -lt "$min" ] && min=$l
            [ "$l" -gt "$max" ] && max=$l
        done
        local avg=$((total / ${#lines_list[@]}))
        local bin_size
        bin_size=$(image_binary_size "$image" "$binary")
        printf "  ─────────────────────────────────────────\n"
        printf "  Avg: %d lines  |  Min: %d  |  Max: %d\n" "$avg" "$min" "$max"
        printf "  Memory  : %s KB\n" "${mem_kb:-N/A}"
        printf "  Binary  : %s\n" "${bin_size:-N/A}"
    fi
    echo ""
}

# ─── Run benchmarks ───────────────────────────────────────────────────────────
run_benchmark "Go"   "las-go"   "/usr/local/bin/log-aggregator"
run_benchmark "Rust" "las-rust" "/usr/local/bin/log-aggregator"
run_benchmark "Zig"  "las-zig"  "/usr/local/bin/log-aggregator"

# ─── Code Lines ───────────────────────────────────────────────────────────────
echo "── Code Lines ────────────────────────────────"
wc -l < "$PROJECT_DIR/go/main.go"       | awk '{printf "  Go  : %s lines\n", $1}'
wc -l < "$PROJECT_DIR/rust/src/main.rs" | awk '{printf "  Rust: %s lines\n", $1}'
wc -l < "$PROJECT_DIR/zig/src/main.zig" | awk '{printf "  Zig : %s lines\n", $1}'
echo ""

# ─── Cleanup ──────────────────────────────────────────────────────────────────
echo "── Cleanup ────────────────────────────────────"
docker rm -f "$BACKEND_CONTAINER" >/dev/null 2>&1
docker network rm "$NETWORK_NAME" >/dev/null 2>&1
echo "  ✓ Done — results saved to: $RESULT_FILE"
echo ""
