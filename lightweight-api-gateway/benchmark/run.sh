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
echo ""

# ─── Start Mock Backend ────────────────────────────────────────────────────────────
echo "── Starting Mock Backend ───────────────────────"
cd "$PROJECT_DIR"
go build -o test-data/mock-backend test-data/mock_backend.go 2>/dev/null || {
    echo "  ✗ Failed to build mock backend"
    exit 1
}

# Start backend in background
./test-data/mock-backend :$BACKEND_PORT &
BACKEND_PID=$!
sleep 2

# Check if backend is running
if ! curl -s http://localhost:$BACKEND_PORT/health >/dev/null 2>&1; then
    echo "  ✗ Backend failed to start"
    kill $BACKEND_PID 2>/dev/null
    exit 1
fi
echo "  ✓ Backend running on port $BACKEND_PORT"

# ─── Build ────────────────────────────────────────────────────────────────────
echo ""
echo "── Building ──────────────────────────────────"

echo "[Go]"
(cd "$PROJECT_DIR/go" && go build -o ../bin/gateway-fiber . 2>&1) \
    && echo "  ✓ bin/gateway-fiber" || echo "  ✗ build failed"

echo "[Rust]"
(cd "$PROJECT_DIR/rust" && cargo build --release 2>&1 | grep -E "^error|Finished|Compiling sub") \
    && echo "  ✓ rust/target/release/lightweight-api-gateway" || echo "  ✗ build failed"

echo "[Zig]"
(cd "$PROJECT_DIR/zig" && zig build -Doptimize=ReleaseFast 2>&1 && \
    cp .zig-cache/o/*/libfacil.io.dylib zig-out/bin/ 2>/dev/null || true) \
    && echo "  ✓ zig/zig-out/bin/lightweight-api-gateway (Zap)" || echo "  ✗ build failed"

echo ""

# ─── Benchmark function ───────────────────────────────────────────────────────
run_benchmark() {
    local name="$1"
    local binary="$2"
    local rps_list=()
    local lat_list=()
    local mem_kb=0
    local WRK_THREADS=4
    local WRK_CONNS=50
    local WRK_DURATION=3s

    printf "── %-6s ─────────────────────────────────────\n" "$name"

    # Start gateway once for all runs
    $binary :$GATEWAY_PORT http://localhost:$BACKEND_PORT >/dev/null 2>&1 &
    GATEWAY_PID=$!
    sleep 1  # Wait for gateway to start

    if ! curl -s http://localhost:$GATEWAY_PORT/health >/dev/null 2>&1; then
        printf "  FAILED (gateway not responding)\n"
        kill $GATEWAY_PID 2>/dev/null
        return
    fi

    # Measure memory of gateway process
    mem_kb=$(ps -o rss= -p $GATEWAY_PID 2>/dev/null | tr -d ' ')

    for i in $(seq 1 $RUNS); do
        local wrk_out
        wrk_out=$(wrk -t$WRK_THREADS -c$WRK_CONNS -d$WRK_DURATION \
            -H "Authorization: Bearer valid-test-token" \
            http://localhost:$GATEWAY_PORT/api/test 2>/dev/null)

        local rps lat_us lat_ms
        rps=$(echo "$wrk_out" | awk '/Requests\/sec/{printf "%.0f", $2}')
        lat_us=$(echo "$wrk_out" | awk '/Latency/{print $2}' | sed 's/us//')
        # Convert latency to ms if it's in us
        if echo "$wrk_out" | grep -q "Latency.*ms"; then
            lat_ms=$(echo "$wrk_out" | awk '/Latency/{printf "%.2f", $2}' | sed 's/ms//')
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

    # Stop gateway
    kill $GATEWAY_PID 2>/dev/null
    wait $GATEWAY_PID 2>/dev/null
    sleep 1

    if [ ${#rps_list[@]} -gt 0 ]; then
        local total=0
        local min=${rps_list[0]}
        local max=${rps_list[0]}
        for r in "${rps_list[@]}"; do
            total=$((total + r))
            [ "$r" -lt "$min" ] && min=$r
            [ "$r" -gt "$max" ] && max=$r
        done
        local avg=$((total / ${#rps_list[@]}))
        printf "  ─────────────────────────────────────────\n"
        printf "  Avg: %d req/s  |  Min: %d  |  Max: %d\n" "$avg" "$min" "$max"
        [ "$mem_kb" -gt 0 ] && printf "  Peak Memory: %d KB\n" "$mem_kb"
    fi
    echo ""
}

# ─── Run benchmarks ───────────────────────────────────────────────────────────
[ -f "$PROJECT_DIR/bin/gateway-fiber" ] && \
    run_benchmark "Go" "$PROJECT_DIR/bin/gateway-fiber"

[ -f "$PROJECT_DIR/rust/target/release/lightweight-api-gateway" ] && \
    run_benchmark "Rust" "$PROJECT_DIR/rust/target/release/lightweight-api-gateway"

[ -f "$PROJECT_DIR/zig/zig-out/bin/lightweight-api-gateway" ] && \
    run_benchmark "Zig" "env DYLD_LIBRARY_PATH=$PROJECT_DIR/zig/zig-out/bin $PROJECT_DIR/zig/zig-out/bin/lightweight-api-gateway"

# ─── Binary Size ──────────────────────────────────────────────────────────────
echo "── Binary Size ───────────────────────────────"
[ -f "$PROJECT_DIR/bin/gateway-fiber" ] && \
    ls -lh "$PROJECT_DIR/bin/gateway-fiber" | awk '{printf "  Go  : %s\n", $5}'
[ -f "$PROJECT_DIR/rust/target/release/lightweight-api-gateway" ] && \
    ls -lh "$PROJECT_DIR/rust/target/release/lightweight-api-gateway" | awk '{printf "  Rust: %s\n", $5}'
[ -f "$PROJECT_DIR/zig/zig-out/bin/lightweight-api-gateway" ] && \
    ls -lh "$PROJECT_DIR/zig/zig-out/bin/lightweight-api-gateway" | awk '{printf "  Zig : %s\n", $5}'

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

# ─── Cleanup ───────────────────────────────────────────────────────────────────
echo "── Cleanup ────────────────────────────────────"
kill $BACKEND_PID 2>/dev/null
rm -f test-data/mock-backend
echo "  ✓ Backend stopped"
echo ""
