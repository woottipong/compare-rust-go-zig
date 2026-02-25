#!/bin/bash
# Benchmark script for Lightweight API Gateway
# Usage: ./benchmark/run.sh
# Run from: lightweight-api-gateway/ directory

RUNS=5         # จำนวนรอบ (รอบแรกถือเป็น warm-up)
WARMUP=1       # จำนวน warm-up runs ที่ไม่นับ average
GATEWAY_PORT=8080
BACKEND_PORT=3000

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "╔══════════════════════════════════════════╗"
echo "║      Lightweight API Gateway Benchmark   ║"
echo "╚══════════════════════════════════════════╝"
echo "  Gateway Port : $GATEWAY_PORT"
echo "  Backend Port : $BACKEND_PORT"
echo "  Runs         : ${RUNS} (${WARMUP} warm-up)"
echo "  Mode         : Docker"
echo ""

# ─── Start Mock Backend ──────────────────────────────────────────────────
echo "── Starting Mock Backend ────────────────────────"
cd "$PROJECT_DIR"

docker build -t gw-mock-backend -f - test-data <<'DOCKEREOF' >/dev/null 2>&1
FROM golang:1.23-bookworm AS builder
WORKDIR /src
COPY . .
RUN go build -o /out/mock-backend mock_backend.go
FROM debian:bookworm-slim
COPY --from=builder /out/mock-backend /usr/local/bin/mock-backend
ENTRYPOINT ["mock-backend"]
DOCKEREOF
docker run -d --name gw-mock-backend --network=host \
    gw-mock-backend ":$BACKEND_PORT" >/dev/null 2>&1
BACKEND_CONTAINER=gw-mock-backend

sleep 2
if ! curl -s http://localhost:$BACKEND_PORT/health >/dev/null 2>&1; then
    echo "  ✗ Backend failed to start"
    docker rm -f "$BACKEND_CONTAINER" 2>/dev/null
    exit 1
fi
echo "  ✓ Backend running on port $BACKEND_PORT"

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
build_image "gw-go"   "$PROJECT_DIR/go"
build_image "gw-rust" "$PROJECT_DIR/rust"
build_image "gw-zig"  "$PROJECT_DIR/zig"
echo ""

# ─── Benchmark function ───────────────────────────────────────────────────────
run_benchmark() {
    local name="$1"
    local image="$2"
    local rps_list=()
    local WRK_THREADS=4
    local WRK_CONNS=50
    local WRK_DURATION=3s
    local CONTAINER_NAME="gw-bench-$$"

    printf "── %-6s (docker) ────────────────────────────\n" "$name"

    # Run gateway container on host network
    docker run -d --name "$CONTAINER_NAME" --network=host \
        "$image" ":$GATEWAY_PORT" "http://localhost:$BACKEND_PORT" >/dev/null 2>&1
    sleep 1

    if ! curl -s http://localhost:$GATEWAY_PORT/health >/dev/null 2>&1; then
        printf "  FAILED (gateway not responding)\n"
        docker rm -f "$CONTAINER_NAME" 2>/dev/null
        return
    fi

    local mem_kb
    mem_kb=$(docker stats --no-stream --format '{{.MemUsage}}' "$CONTAINER_NAME" 2>/dev/null | \
        awk '{gsub(/MiB/,""); printf "%.0f", $1*1024}')

    for i in $(seq 1 $RUNS); do
        local wrk_out rps lat_ms
        wrk_out=$(wrk -t$WRK_THREADS -c$WRK_CONNS -d$WRK_DURATION \
            -H "Authorization: Bearer valid-test-token" \
            http://localhost:$GATEWAY_PORT/api/test 2>/dev/null)
        rps=$(echo "$wrk_out" | awk '/Requests\/sec/{printf "%.0f", $2}')
        if echo "$wrk_out" | grep -q "Latency.*ms"; then
            lat_ms=$(echo "$wrk_out" | awk '/Latency/{printf "%.2f", $2}')
        else
            lat_ms=$(echo "$wrk_out" | awk '/Latency/{printf "%.3f", $2/1000}')
        fi

        if [ -z "$rps" ]; then
            printf "  Run %d: FAILED\n" "$i"
            continue
        fi
        if [ "$i" -le "$WARMUP" ]; then
            printf "  Run %d (warm-up): %s req/s  latency %sms\n" "$i" "$rps" "$lat_ms"
        else
            printf "  Run %d           : %s req/s  latency %sms\n" "$i" "$rps" "$lat_ms"
            rps_list+=("$rps")
        fi
    done

    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
    sleep 1

    if [ ${#rps_list[@]} -gt 0 ]; then
        local total=0 min=${rps_list[0]} max=${rps_list[0]}
        for r in "${rps_list[@]}"; do
            total=$((total + r))
            [ "$r" -lt "$min" ] && min=$r
            [ "$r" -gt "$max" ] && max=$r
        done
        printf "  ─────────────────────────────────────────\n"
        printf "  Avg: %d req/s  |  Min: %d  |  Max: %d\n" "$((total / ${#rps_list[@]}))" "$min" "$max"
        [ "$mem_kb" -gt 0 ] && printf "  Peak Memory: %d KB\n" "$mem_kb"
    fi
    echo ""
}

# ─── Run benchmarks ───────────────────────────────────────────────────────────
run_benchmark "Go"   "gw-go"
run_benchmark "Rust" "gw-rust"
run_benchmark "Zig"  "gw-zig"

# ─── Code Lines ───────────────────────────────────────────────────────────────
echo "── Code Lines ────────────────────────────────"
wc -l < "$PROJECT_DIR/go/main.go"       | awk '{printf "  Go  : %s lines\n", $1}'
wc -l < "$PROJECT_DIR/rust/src/main.rs" | awk '{printf "  Rust: %s lines\n", $1}'
wc -l < "$PROJECT_DIR/zig/src/main.zig" | awk '{printf "  Zig : %s lines\n", $1}'

echo ""

# ─── Cleanup ──────────────────────────────────────────────────────────────────
echo "── Cleanup ────────────────────────────────────"
docker rm -f "$BACKEND_CONTAINER" 2>/dev/null
echo "  ✓ Backend container stopped"
echo ""
