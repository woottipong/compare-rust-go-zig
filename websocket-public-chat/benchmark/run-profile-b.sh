#!/bin/bash

set -euo pipefail
export LC_ALL=C

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
K6_DIR="$PROJECT_DIR/k6"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_FILE="$SCRIPT_DIR/results/websocket_profile_b_${TIMESTAMP}.txt"
RESULT_LATEST_FILE="$SCRIPT_DIR/results/websocket_profile_b_latest.txt"
NETWORK="ws-bench-net"

# k6 scenario durations + server buffer (server must outlive k6 run)
# k6: steady=60s, burst=20s, churn=60s, saturation=100s (10+20+10+20+10+20+10)
STEADY_SRV_SEC=70
BURST_SRV_SEC=30
CHURN_SRV_SEC=70
SAT_SRV_SEC=115
LANGUAGES=(go rust zig)

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
    if docker build -q -t "wsc-${lang}" "$PROJECT_DIR/profile-b/$lang/" >/dev/null 2>&1; then
        echo " ✓"
    else
        echo " ✗"; die "Build failed for $lang"
    fi
}

# Start server; wait until it prints "listening"
start_server() {
    local image=$1 cname=$2
    shift 2
    docker rm -f "$cname" >/dev/null 2>&1 || true   # remove stale container if present
    docker run -d --network "$NETWORK" --name "$cname" "$image" "$@" >/dev/null
    local i=0
    while [ $i -lt 20 ]; do
        if docker logs "$cname" 2>&1 | grep -qiE "listening|port"; then
            break
        fi
        sleep 0.5; i=$((i+1))
    done
}

# Run k6 scenario; collect all output (no --quiet → full metric summary with p95/p99)
run_k6() {
    local scenario=$1 server_name=$2
    docker run --rm --network "$NETWORK" \
        wsc-k6 run --no-color \
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


parse_throughput()  { printf '%s' "$1" | grep "Throughput:"        | awk -F': ' '{print $2}' | awk '{print $1}'; }
parse_messages()    { printf '%s' "$1" | grep "Total messages:"    | awk -F': ' '{print $2}'; }
parse_conns()       { printf '%s' "$1" | grep "Total connections:" | awk -F': ' '{print $2}'; }
parse_dropped()     { printf '%s' "$1" | grep "Message drop rate:" | awk -F': ' '{print $2}'; }
# p(95) of WebSocket connection establishment time (from k6 end-of-test summary)
parse_p95_connect() { printf '%s' "$1" | grep -E "ws_connect_duration|ws_connecting" | sed 's/.*p(95)=\([^ ]*\).*/\1/' || true; }
# Key k6 metric lines: checks, ws sessions, messages, errors, connect latency
parse_k6_summary()  { printf '%s' "$1" | grep -E "^\s+(checks|ws_sessions|ws_msgs_received|ws_errors|ws_connect_duration|ws_connecting)" | sed 's/^/    /' || true; }

configure_server_args() {
    local lang=$1

    case "$lang" in
        go)
            s_args=(--duration "$STEADY_SRV_SEC")
            b_args=(--duration "$BURST_SRV_SEC")
            c_args=(--duration "$CHURN_SRV_SEC")
            sat_args=(--duration "$SAT_SRV_SEC")
            ;;
        rust)
            s_args=(--port 8080 --duration "$STEADY_SRV_SEC")
            b_args=(--port 8080 --duration "$BURST_SRV_SEC")
            c_args=(--port 8080 --duration "$CHURN_SRV_SEC")
            sat_args=(--port 8080 --duration "$SAT_SRV_SEC")
            ;;
        zig)
            s_args=(8080 "$STEADY_SRV_SEC")
            b_args=(8080 "$BURST_SRV_SEC")
            c_args=(8080 "$CHURN_SRV_SEC")
            sat_args=(8080 "$SAT_SRV_SEC")
            ;;
        *)
            die "Unknown language: $lang"
            ;;
    esac
}

run_scenario() {
    local lang=$1 scenario=$2 srv_sec=$3
    shift 3
    # $@ = server args

    local image="wsc-${lang}"
    local cname="${lang}-${scenario}"
    local mem_file="/tmp/wsc_${lang}_${scenario}_mem"

    start_server "$image" "$cname" "$@"

    # Sample peak memory in background while k6 runs.
    # Inline (no subshell) so $! is set correctly on bash 3.2/macOS.
    # Write the running max to $mem_file on every new high-water mark so
    # the file is readable even when the sampler is killed mid-loop.
    echo "0" > "$mem_file"
    {
        peak=0
        while true; do
            raw=$(docker stats --no-stream --format "{{.MemUsage}}" "$cname" 2>/dev/null) || break
            [ -z "$raw" ] && break
            mib=$(echo "$raw" | awk '{s=$1; val=s+0; if (index(s,"GiB")>0||index(s,"GB")>0) val=val*1024; else if (index(s,"KiB")>0||index(s,"kB")>0) val=val/1024; printf "%.0f", val}' 2>/dev/null)
            if [ -n "$mib" ] && [ "$mib" -gt "$peak" ] 2>/dev/null; then
                peak=$mib
                echo "$peak" > "$mem_file"
            fi
            sleep 1
        done
    } &
    local mem_pid=$!

    local k6_out; k6_out=$(run_k6 "$scenario" "$cname")

    kill "$mem_pid" 2>/dev/null || true
    wait "$mem_pid" 2>/dev/null || true

    local srv_out; srv_out=$(wait_and_collect "$cname")
    local peak_mem; peak_mem=$(cat "$mem_file" 2>/dev/null || echo "0")
    rm -f "$mem_file"

    local tp;  tp=$(parse_throughput "$srv_out");    tp="${tp:-0}"
    local p95; p95=$(parse_p95_connect "$k6_out"); p95="${p95:-N/A}"

    echo "    throughput:   $tp msg/s"
    echo "    messages:     $(parse_messages "$srv_out")"
    echo "    connections:  $(parse_conns "$srv_out")"
    echo "    drop rate:    $(parse_dropped "$srv_out")"
    echo "    connect p95:  $p95"
    echo "    peak memory:  ${peak_mem} MiB"
    echo "    k6:"
    parse_k6_summary "$k6_out"

    printf '%s' "$tp"       > "/tmp/wsc_${lang}_${scenario}_tp"
    printf '%s' "$p95"      > "/tmp/wsc_${lang}_${scenario}_p95"
    printf '%s' "$peak_mem" > "/tmp/wsc_${lang}_${scenario}_mem_peak"
}

run_language_scenarios() {
    local lang=$1

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $lang"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    configure_server_args "$lang"

    echo ""
    echo "  [1/4] steady     — 100 VUs × 1 msg/s × 60s"
    run_scenario "$lang" steady "$STEADY_SRV_SEC" "${s_args[@]}"

    echo ""
    echo "  [2/4] burst      — 0→1000 VUs in 10s, hold 5s, ramp-down 5s"
    run_scenario "$lang" burst "$BURST_SRV_SEC" "${b_args[@]}"

    echo ""
    echo "  [3/4] churn      — 200 VUs × connect→2s→leave × 60s"
    run_scenario "$lang" churn "$CHURN_SRV_SEC" "${c_args[@]}"

    echo ""
    echo "  [4/4] saturation — 200→500→1000 VUs × 5 msg/s (finds throughput ceiling)"
    run_scenario "$lang" saturation "$SAT_SRV_SEC" "${sat_args[@]}"

    echo ""
}

print_summary_table() {
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                       Results Summary                           ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""
    printf "%-8s  %14s  %13s  %18s  %10s\n" \
        "Language" "Steady (msg/s)" "Burst (msg/s)" "Saturation (msg/s)" "Peak Mem"
    printf "%-8s  %14s  %13s  %18s  %10s\n" \
        "────────" "──────────────" "─────────────" "──────────────────" "────────"

    for lang in "${LANGUAGES[@]}"; do
        st=$(cat  "/tmp/wsc_${lang}_steady_tp"       2>/dev/null || echo "N/A")
        bu=$(cat  "/tmp/wsc_${lang}_burst_tp"        2>/dev/null || echo "N/A")
        sa=$(cat  "/tmp/wsc_${lang}_saturation_tp"   2>/dev/null || echo "N/A")
        mem=$(cat "/tmp/wsc_${lang}_steady_mem_peak" 2>/dev/null || echo "N/A")
        printf "%-8s  %14s  %13s  %18s  %10s\n" "$lang" "$st" "$bu" "$sa" "${mem} MiB"
    done
}

# ── banner ─────────────────────────────────────────────────────────────────

echo "╔════════════════════════════════════════════╗"
echo "║  WebSocket Public Chat — Profile B         ║"
echo "║  Steady / Burst / Churn / Saturation (k6)  ║"
echo "╚════════════════════════════════════════════╝"
echo "Date: $(date)"
echo

require_docker
ensure_network

# ── build ──────────────────────────────────────────────────────────────────

echo "Building images..."
for lang in "${LANGUAGES[@]}"; do
    build_image "$lang"
done

printf "  %-6s" "k6:"
if docker build -q -t wsc-k6 "$K6_DIR" >/dev/null 2>&1; then echo " ✓"; else echo " ✗"; die "k6 build failed"; fi
echo

# ── run benchmark ──────────────────────────────────────────────────────────

for lang in "${LANGUAGES[@]}"; do
    run_language_scenarios "$lang"
done

# ── summary table ──────────────────────────────────────────────────────────

print_summary_table
rm -f /tmp/wsc_*_*_tp /tmp/wsc_*_*_p95 /tmp/wsc_*_*_mem_peak

# ── binary sizes ───────────────────────────────────────────────────────────

echo ""
echo "Binary sizes:"
for lang in "${LANGUAGES[@]}"; do
    image="wsc-${lang}"
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

cp "$RESULT_FILE" "$RESULT_LATEST_FILE"

echo "Latest profile B text: $RESULT_LATEST_FILE"
