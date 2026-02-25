#!/bin/bash
# Benchmark script for High-Performance Reverse Proxy
# Usage: ./benchmark/run.sh
# Run from: high-perf-reverse-proxy/ directory

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$SCRIPT_DIR/results"
RESULT_FILE="$RESULTS_DIR/high-perf-reverse-proxy_$(date +%Y%m%d_%H%M%S).txt"

mkdir -p "$RESULTS_DIR"
exec > >(tee -a "$RESULT_FILE")

NETWORK_NAME="hprp-bench-net"

echo "╔══════════════════════════════════════════╗"
echo "║  High-Performance Reverse Proxy Benchmark ║"
echo "╚══════════════════════════════════════════╝"
echo ""

cleanup() {
    echo "Cleaning up..."
    docker rm -f hprp-mock-backend1 hprp-mock-backend2 hprp-mock-backend3 \
        hprp-go hprp-rust hprp-zig \
        hprp-Go hprp-Rust hprp-Zig 2>/dev/null
    docker network rm "$NETWORK_NAME" 2>/dev/null
}
trap cleanup EXIT

echo "── Setup ────────────────────────────────────"
docker network create "$NETWORK_NAME" 2>/dev/null || true

# Create mock backend image with inline Dockerfile
MOCK_DIR="/tmp/hprp-mock"
rm -rf "$MOCK_DIR" && mkdir -p "$MOCK_DIR"

cat > "$MOCK_DIR/Dockerfile" << 'EOF'
FROM python:3.12-slim
WORKDIR /app
RUN pip install --no-cache-dir aiohttp
COPY server.py /app/
CMD ["python", "server.py"]
EOF

cat > "$MOCK_DIR/server.py" << 'EOF'
from aiohttp import web

async def handler(request):
    return web.Response(text="OK", status=200)

app = web.Application()
app.router.add_get('/', handler)
app.router.add_get('/health', handler)
web.run_app(app, host='0.0.0.0', port=3000)
EOF

echo "Building mock backend..."
docker build -t hprp-mock-backend "$MOCK_DIR" 2>&1 | tail -2

# Run 3 mock backends
echo "Starting mock backends..."
docker run -d --network "$NETWORK_NAME" --name hprp-mock-backend1 hprp-mock-backend &
docker run -d --network "$NETWORK_NAME" --name hprp-mock-backend2 hprp-mock-backend &
docker run -d --network "$NETWORK_NAME" --name hprp-mock-backend3 hprp-mock-backend &
sleep 3

# Build proxy images
echo ""
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
build_image "hprp-go"   "$PROJECT_DIR/go"
build_image "hprp-rust" "$PROJECT_DIR/rust"
build_image "hprp-zig"  "$PROJECT_DIR/zig"
echo ""

# backends format per language:
#   Go   needs  http://host:port  (uses httputil.ReverseProxy)
#   Rust needs  host:port         (raw TCP)
#   Zig  needs  host:port         (raw TCP)
GO_BACKENDS="http://hprp-mock-backend1:3000,http://hprp-mock-backend2:3000,http://hprp-mock-backend3:3000"
TCP_BACKENDS="hprp-mock-backend1:3000,hprp-mock-backend2:3000,hprp-mock-backend3:3000"

# Benchmark function
run_benchmark() {
    local name="$1" image="$2" backends="$3"

    printf "── %-4s ───────────────────────────────────────\n" "$name"

    # Run proxy container
    docker run -d --network "$NETWORK_NAME" -p 8080:8080 --name "hprp-$name" "$image" \
        --port 8080 --backends "$backends" >/dev/null

    # Wait for proxy to be ready (up to 15s)
    local ready=0
    for i in $(seq 1 30); do
        if curl -sf http://localhost:8080/ >/dev/null 2>&1; then
            ready=1
            break
        fi
        sleep 0.5
    done

    if [ "$ready" -eq 0 ]; then
        echo "  FAILED to start — container logs:"
        docker logs "hprp-$name" 2>&1 | tail -5
        docker rm -f "hprp-$name" >/dev/null 2>&1
        echo ""
        return
    fi

    # Run wrk
    local wrk_output req_sec latency
    wrk_output=$(wrk -t4 -c50 -d5s http://localhost:8080/ 2>&1)
    req_sec=$(echo "$wrk_output" | grep "Requests/sec:" | awk '{print $2}')
    latency=$(echo "$wrk_output" | grep "Latency" | awk '{print $2}')

    if [ -n "$req_sec" ]; then
        printf "  Requests/sec : %s\n" "$req_sec"
        printf "  Avg Latency  : %s\n" "$latency"
    else
        echo "  FAILED — wrk output:"
        echo "$wrk_output"
    fi

    docker rm -f "hprp-$name" >/dev/null 2>&1
    sleep 1
    echo ""
}

# Run benchmarks
run_benchmark "go"   "hprp-go"   "$GO_BACKENDS"
run_benchmark "rust" "hprp-rust" "$TCP_BACKENDS"
run_benchmark "zig"  "hprp-zig"  "$TCP_BACKENDS"

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

echo "  Go  : $(get_binary_size hprp-go   /usr/local/bin/hprp-go)"
echo "  Rust: $(get_binary_size hprp-rust /usr/local/bin/hprp-rust)"
echo "  Zig : $(get_binary_size hprp-zig  /usr/local/bin/hprp-zig)"
echo ""

# Code Lines
echo "── Code Lines ────────────────────────────────"
wc -l < "$PROJECT_DIR/go/main.go"       | awk '{printf "  Go  : %s lines\n", $1}'
wc -l < "$PROJECT_DIR/rust/src/main.rs" | awk '{printf "  Rust: %s lines\n", $1}'
wc -l < "$PROJECT_DIR/zig/src/main.zig" | awk '{printf "  Zig : %s lines\n", $1}'
echo ""

echo "── Results saved to ──────────────────────────"
echo "  $RESULT_FILE"
