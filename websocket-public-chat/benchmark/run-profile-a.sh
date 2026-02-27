#!/bin/bash

set -euo pipefail
export LC_ALL=C

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
K6_DIR="$PROJECT_DIR/k6"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_FILE="$SCRIPT_DIR/results/websocket_profile_a_${TIMESTAMP}.txt"
NETWORK="ws-bench-net"

# Server duration must exceed k6 test duration so the server exits naturally.
# k6: steady=60s, burst=20s, churn=60s
STEADY_SRV_SEC=70
BURST_SRV_SEC=30
CHURN_SRV_SEC=70

mkdir -p "$SCRIPT_DIR/results"
exec > >(tee -a "$RESULT_FILE") 2>&1

# ── helpers ────────────────────────────────────────────────────────────────

die() { echo "❌ $1"; exit 1; }

require_docker() {
    docker info >/dev/null 2>&1 || die "Docker daemon not running"
}

ensure_network() {
    docker network inspect "$NETWORK" >/dev/null 2>&1 \
        || docker network create "$NETWORK" >/dev/null
}

build_image() {
    local lang=$1
    printf "  %-6s" "$lang:"
    if docker build -q -t "wsca-${lang}" "$PROJECT_DIR/profile-a/$lang/" >/dev/null 2>&1; then
        echo " ✓"
    else
        echo " ✗"; die "Build failed for $lang"
    fi
}

# Start server; wait until it prints "listening"
start_server() {
    local image=$1 cname=$2
    shift 2
    docker run -d --network "$NETWORK" --name "$cname" "$image" "$@" >/dev/null
    local i=0
    while [ $i -lt 20 ]; do
        docker logs "$cname" 2>&1 | grep -qiE "listening|port" && break
        sleep 0.5; i=$((i+1))
    done
}

# Run k6 scenario; collect stdout
run_k6() {
    local scenario=$1 server_name=$2
    docker run --rm --network "$NETWORK" \
        wsc-k6 run --no-color --quiet \
        -e "WS_URL=ws://${server_name}:8080/ws" \
        "/scripts/${scenario}.js" 2>&1 || true
}

# Wait for container to exit naturally, collect logs, then remove
wait_and_collect() {
    local cname=$1
    docker wait "$cname" >/dev/null 2>&1 || true
    docker logs "$cname" 2>&1 || true
    docker rm "$cname" >/dev/null 2>&1 || true
}

parse_throughput() { printf '%s' "$1" | grep "Throughput:"        | awk -F': ' '{print $2}' | awk '{print $1}'; }
parse_messages()   { printf '%s' "$1" | grep "Total messages:"    | awk -F': ' '{print $2}'; }
parse_conns()      { printf '%s' "$1" | grep "Total connections:" | awk -F': ' '{print $2}'; }
parse_dropped()    { printf '%s' "$1" | grep "Message drop rate:" | awk -F': ' '{print $2}'; }
parse_k6_summary() { printf '%s' "$1" | grep -E "checks_succeeded|ws_sessions|ws_msgs_received|ws_errors" | head -4 | sed 's/^/    /'; }

run_scenario() {
    local lang=$1 scenario=$2 srv_sec=$3
    shift 3
    # $@ = server args

    local image="wsca-${lang}"
    local cname="${lang}-a-${scenario}"   # -a- prefix avoids collision with profile-b containers

    start_server "$image" "$cname" "$@"
    local k6_out; k6_out=$(run_k6 "$scenario" "$cname")
    local srv_out; srv_out=$(wait_and_collect "$cname")

    local tp; tp=$(parse_throughput "$srv_out"); tp="${tp:-0}"
    echo "    throughput:   $tp msg/s"
    echo "    messages:     $(parse_messages "$srv_out")"
    echo "    connections:  $(parse_conns "$srv_out")"
    echo "    drop rate:    $(parse_dropped "$srv_out")"
    echo "    k6:"
    parse_k6_summary "$k6_out"

    printf '%s' "$tp" > "/tmp/wsca_${lang}_${scenario}_tp"
}

# ── banner ─────────────────────────────────────────────────────────────────

echo "╔════════════════════════════════════════╗"
echo "║  WebSocket Public Chat — Profile A     ║"
echo "║  Framework: GoFiber / Axum / zap       ║"
echo "╚════════════════════════════════════════╝"
echo "Date: $(date)"
echo

require_docker
ensure_network

# ── build ──────────────────────────────────────────────────────────────────

echo "Building images..."
build_image go
build_image rust
build_image zig

printf "  %-6s" "k6:"
if docker build -q -t wsc-k6 "$K6_DIR" >/dev/null 2>&1; then echo " ✓"; else echo " ✗"; die "k6 build failed"; fi
echo

# ── run benchmark ──────────────────────────────────────────────────────────

for lang in go rust zig; do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $lang"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    case "$lang" in
        go)
            s_args=(--duration "$STEADY_SRV_SEC")
            b_args=(--duration "$BURST_SRV_SEC")
            c_args=(--duration "$CHURN_SRV_SEC")
            ;;
        rust)
            s_args=(--port 8080 --duration "$STEADY_SRV_SEC")
            b_args=(--port 8080 --duration "$BURST_SRV_SEC")
            c_args=(--port 8080 --duration "$CHURN_SRV_SEC")
            ;;
        zig)
            s_args=(8080 "$STEADY_SRV_SEC")
            b_args=(8080 "$BURST_SRV_SEC")
            c_args=(8080 "$CHURN_SRV_SEC")
            ;;
    esac

    echo ""
    echo "  [1/3] steady — 100 VUs × 1 msg/s × 60s"
    run_scenario "$lang" steady "$STEADY_SRV_SEC" "${s_args[@]}"

    echo ""
    echo "  [2/3] burst  — 0→1000 VUs in 10s, hold 5s, ramp-down 5s"
    run_scenario "$lang" burst "$BURST_SRV_SEC" "${b_args[@]}"

    echo ""
    echo "  [3/3] churn  — 200 VUs × connect→2s→leave × 60s"
    run_scenario "$lang" churn "$CHURN_SRV_SEC" "${c_args[@]}"

    echo ""
done

# ── summary table ──────────────────────────────────────────────────────────

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║               Profile A — Results Summary                   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
printf "%-8s  %22s  %22s  %22s\n" "Language" "Steady (msg/s)" "Burst (msg/s)" "Churn (msg/s)"
printf "%-8s  %22s  %22s  %22s\n" "────────" "──────────────────────" "──────────────────────" "──────────────────────"
for lang in go rust zig; do
    st=$(cat "/tmp/wsca_${lang}_steady_tp" 2>/dev/null || echo "N/A")
    bu=$(cat "/tmp/wsca_${lang}_burst_tp"  2>/dev/null || echo "N/A")
    ch=$(cat "/tmp/wsca_${lang}_churn_tp"  2>/dev/null || echo "N/A")
    printf "%-8s  %22s  %22s  %22s\n" "$lang" "$st" "$bu" "$ch"
done
rm -f /tmp/wsca_*_*_tp

# ── binary sizes ───────────────────────────────────────────────────────────

echo ""
echo "Binary sizes:"
for lang in go rust zig; do
    image="wsca-${lang}"
    cid=$(docker create "$image" 2>/dev/null)
    raw=$(docker cp "${cid}:/usr/local/bin/websocket-public-chat" - 2>/dev/null | wc -c)
    docker rm "$cid" >/dev/null 2>/dev/null || true
    if [ "$raw" -lt 1048576 ]; then
        fmt=$(echo "scale=1; $raw / 1024" | bc -l)
        echo "  $lang: ${fmt} KB"
    else
        fmt=$(echo "scale=2; $raw / 1048576" | bc -l)
        echo "  $lang: ${fmt} MB"
    fi
done

echo ""
echo "Results saved to: $RESULT_FILE"
