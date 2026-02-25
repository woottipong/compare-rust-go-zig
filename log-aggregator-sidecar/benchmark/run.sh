#!/bin/bash
# Benchmark script for Log Aggregator Sidecar
# Usage: bash benchmark/run.sh
# Run from: log-aggregator-sidecar/ directory

set -e

RUNS=5
WARMUP=1
TEST_FILE="test-data/app.log"
MOCK_PORT=9200
NETWORK_NAME="las-bench-net"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$SCRIPT_DIR/results"
mkdir -p "$RESULTS_DIR"
RESULT_FILE="$RESULTS_DIR/log-aggregator-sidecar_$(date +%Y%m%d_%H%M%S).txt"

exec > >(tee -a "$RESULT_FILE") 2>&1

echo "╔══════════════════════════════════════════╗"
echo "║     Log Aggregator Sidecar Benchmark     ║"
echo "╚══════════════════════════════════════════╝"
echo "  Test File: $TEST_FILE"
echo "  Mock Port : $MOCK_PORT"
echo "  Runs      : ${RUNS} (${WARMUP} warm-up)"
echo "  Mode      : Docker (one-shot)"
echo ""

# ─── Generate test data if needed ────────────────────────────────────────────
if [ ! -f "$PROJECT_DIR/$TEST_FILE" ]; then
    echo "── Generating Test Data ─────────────────────────"
    mkdir -p "$PROJECT_DIR/test-data"
    python3 -c "
import random, time
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
echo "  ✓ Backend running on port $MOCK_PORT"

# ─── Build ────────────────────────────────────────────────────────────────────
echo ""
echo "── Building ──────────────────────────────────────"
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

# ─── Binary size ──────────────────────────────────────────────────────────────
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

# ─── Benchmark function (one-shot mode) ──────────────────────────────────────
run_benchmark() {
    local name="$1"
    local image="$2"
    local binary="$3"
    local throughputs=()

    printf "── %-6s ────────────────────────────────────────\n" "$name"

    for i in $(seq 1 $RUNS); do
        local output
        output=$(docker run --rm \
            --network "$NETWORK_NAME" \
            -v "$PROJECT_DIR/test-data:/logs:ro" \
            "$image" \
            --input "/logs/app.log" \
            --output "http://las-mock-backend:9200" \
            --workers 4 \
            --buffer 10000 \
            --one-shot 2>&1)

        local throughput
        throughput=$(echo "$output" | grep "Throughput:" | awk -F': ' '{print $2}' | awk '{print $1}')
        if [ -z "$throughput" ]; then
            throughput="0"
        fi

        if [ "$i" -le "$WARMUP" ]; then
            printf "  Run %d (warm-up): %s lines/sec\n" "$i" "$throughput"
        else
            printf "  Run %d           : %s lines/sec\n" "$i" "$throughput"
            throughputs+=("$throughput")
        fi
    done

    if [ ${#throughputs[@]} -gt 0 ]; then
        local avg min max
        avg=$(printf '%s\n' "${throughputs[@]}" | awk '{s+=$1; n++} END{printf "%.0f", s/n}')
        min=$(printf '%s\n' "${throughputs[@]}" | sort -n | head -1 | awk '{printf "%.0f", $1}')
        max=$(printf '%s\n' "${throughputs[@]}" | sort -n | tail -1 | awk '{printf "%.0f", $1}')
        local bin_size
        bin_size=$(image_binary_size "$image" "$binary")
        printf "  ─────────────────────────────────────────────\n"
        printf "  Avg: %s l/s  |  Min: %s  |  Max: %s\n" "$avg" "$min" "$max"
        printf "  Binary  : %s\n" "${bin_size:-N/A}"
    fi
    echo ""
}

# ─── Run benchmarks ───────────────────────────────────────────────────────────
run_benchmark "Go"   "las-go"   "/usr/local/bin/log-aggregator"
run_benchmark "Rust" "las-rust" "/usr/local/bin/log-aggregator"
run_benchmark "Zig"  "las-zig"  "/usr/local/bin/log-aggregator"

# ─── Code Lines ───────────────────────────────────────────────────────────────
echo "── Code Lines ────────────────────────────────────"
wc -l < "$PROJECT_DIR/go/main.go"       | awk '{printf "  Go  : %s lines\n", $1}'
wc -l < "$PROJECT_DIR/rust/src/main.rs" | awk '{printf "  Rust: %s lines\n", $1}'
wc -l < "$PROJECT_DIR/zig/src/main.zig" | awk '{printf "  Zig : %s lines\n", $1}'
echo ""

# ─── Cleanup ──────────────────────────────────────────────────────────────────
echo "── Cleanup ───────────────────────────────────────"
docker rm -f "$BACKEND_CONTAINER" >/dev/null 2>&1
docker network rm "$NETWORK_NAME" >/dev/null 2>&1
echo "  ✓ Done — results saved to: $RESULT_FILE"
echo ""
