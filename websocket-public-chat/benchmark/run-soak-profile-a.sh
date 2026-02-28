#!/bin/bash

set -euo pipefail
export LC_ALL=C

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
K6_DIR="$PROJECT_DIR/k6"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_FILE="$SCRIPT_DIR/results/websocket_soak_profile_a_${TIMESTAMP}.txt"
RESULT_LATEST_FILE="$SCRIPT_DIR/results/websocket_soak_profile_a_latest.txt"
NETWORK="ws-bench-net"

# k6 soak scenario durations + server buffer (server must outlive k6 run)
# k6: steady-soak=300s, churn-soak=180s
STEADY_SOAK_SRV_SEC=315   # 300s + 15s buffer
CHURN_SOAK_SRV_SEC=195    # 180s + 15s buffer
LANGUAGES=(go rust zig)

# Memory drift windows: compare first vs last N seconds of each soak run
DRIFT_WINDOW_SEC=60

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
    docker rm -f "$cname" >/dev/null 2>&1 || true
    docker run -d --network "$NETWORK" --name "$cname" --cpus 2 --memory 512m "$image" "$@" >/dev/null
    local i=0
    while [ $i -lt 20 ]; do
        if docker logs "$cname" 2>&1 | grep -qiE "listening|port"; then
            break
        fi
        sleep 0.5; i=$((i+1))
    done
}

# Run k6 soak scenario
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
parse_p95_connect() { printf '%s' "$1" | grep -E "ws_connect_duration|ws_connecting" | sed 's/.*p(95)=\([^ ]*\).*/\1/' || true; }
parse_k6_summary()  { printf '%s' "$1" | grep -E "^\s+(checks|ws_sessions|ws_msgs_received|ws_errors|ws_connect_duration|ws_connecting)" | sed 's/^/    /' || true; }

# Extract ws_errors count from k6 summary for error accumulation metric
parse_ws_errors_total() {
    printf '%s' "$1" | grep -E "^\s+ws_errors" | awk '{print $2}' | tr -d ',' || echo "0"
}

# Compute peak of a file containing one number per line; returns 0 if empty
file_peak() {
    local val
    val=$(sort -n "$1" 2>/dev/null | tail -1)
    echo "${val:-0}"
}

configure_server_args() {
    local lang=$1 srv_sec=$2

    case "$lang" in
        go)
            soak_args=(--duration "$srv_sec")
            ;;
        rust)
            soak_args=(--port 8080 --duration "$srv_sec")
            ;;
        zig)
            soak_args=(8080 "$srv_sec")
            ;;
        *)
            die "Unknown language: $lang"
            ;;
    esac
}

run_scenario_soak() {
    local lang=$1 scenario=$2 srv_sec=$3
    shift 3
    # $@ = server args

    local image="wsca-${lang}"
    local cname="${lang}-soak-${scenario}"
    local mem_file="/tmp/wsca_${lang}_${scenario}_mem"
    local mem_early_file="/tmp/wsca_${lang}_${scenario}_mem_early"
    local mem_late_file="/tmp/wsca_${lang}_${scenario}_mem_late"

    # k6 duration is srv_sec minus 15s buffer
    local k6_duration_sec=$((srv_sec - 15))

    start_server "$image" "$cname" "$@"

    # Sample memory in background; track early and late windows for drift analysis.
    # late_start = 75% of k6 duration so we always capture late samples even if
    # docker stats runs slower than 1 sample/sec.
    echo "0" > "$mem_file"
    > "$mem_early_file"
    > "$mem_late_file"
    {
        peak=0
        sample_idx=0
        late_start=$((k6_duration_sec * 3 / 4))
        while true; do
            raw=$(docker stats --no-stream --format "{{.MemUsage}}" "$cname" 2>/dev/null) || break
            [ -z "$raw" ] && break
            mib=$(echo "$raw" | awk '{s=$1; val=s+0; if (index(s,"GiB")>0||index(s,"GB")>0) val=val*1024; else if (index(s,"KiB")>0||index(s,"kB")>0) val=val/1024; printf "%.0f", val}' 2>/dev/null)
            if [ -n "$mib" ]; then
                if [ "$mib" -gt "$peak" ] 2>/dev/null; then
                    peak=$mib
                    echo "$peak" > "$mem_file"
                fi
                if [ "$sample_idx" -lt "$DRIFT_WINDOW_SEC" ] 2>/dev/null; then
                    echo "$mib" >> "$mem_early_file"
                fi
                if [ "$sample_idx" -ge "$late_start" ] 2>/dev/null; then
                    echo "$mib" >> "$mem_late_file"
                fi
            fi
            sample_idx=$((sample_idx + 1))
            sleep 1
        done
    } &
    local mem_pid=$!

    local cpu_file="/tmp/wsca_${lang}_${scenario}_cpu"
    echo "0" > "$cpu_file"
    {
        peak_cpu=0
        while true; do
            raw=$(docker stats --no-stream --format "{{.CPUPerc}}" "$cname" 2>/dev/null) || break
            [ -z "$raw" ] && break
            cpu_val=$(echo "$raw" | tr -d '%' | awk '{printf "%.0f", $1}')
            if [ -n "$cpu_val" ] && [ "$cpu_val" -gt "$peak_cpu" ] 2>/dev/null; then
                peak_cpu=$cpu_val
                echo "$peak_cpu" > "$cpu_file"
            fi
            sleep 1
        done
    } &
    local cpu_pid=$!

    local k6_out; k6_out=$(run_k6 "$scenario" "$cname")

    kill "$mem_pid" "$cpu_pid" 2>/dev/null || true
    wait "$mem_pid" "$cpu_pid" 2>/dev/null || true

    local srv_out; srv_out=$(wait_and_collect "$cname")
    local peak_mem; peak_mem=$(cat "$mem_file" 2>/dev/null || echo "0")
    local early_peak; early_peak=$(file_peak "$mem_early_file")
    local late_peak; late_peak=$(file_peak "$mem_late_file")
    rm -f "$mem_file" "$mem_early_file" "$mem_late_file"
    local peak_cpu; peak_cpu=$(cat "$cpu_file" 2>/dev/null || echo "0")
    rm -f "$cpu_file"

    # Compute memory drift (late - early); negative means memory decreased
    local mem_drift="N/A"
    if [ "$early_peak" != "0" ] && [ -n "$early_peak" ] && [ "$late_peak" != "0" ] && [ -n "$late_peak" ]; then
        mem_drift=$((late_peak - early_peak))
    fi

    # Error accumulation: ws_errors / duration_sec
    local ws_errors_total; ws_errors_total=$(parse_ws_errors_total "$k6_out")
    ws_errors_total="${ws_errors_total:-0}"
    local ws_err_per_sec="N/A"
    if echo "$ws_errors_total" | grep -qE '^[0-9]+$'; then
        ws_err_per_sec=$(awk "BEGIN {printf \"%.3f\", $ws_errors_total / $k6_duration_sec}")
    fi

    local tp;  tp=$(parse_throughput "$srv_out");    tp="${tp:-0}"
    local p95; p95=$(parse_p95_connect "$k6_out"); p95="${p95:-N/A}"

    echo "    throughput:   $tp msg/s"
    echo "    messages:     $(parse_messages "$srv_out")"
    echo "    connections:  $(parse_conns "$srv_out")"
    echo "    drop rate:    $(parse_dropped "$srv_out")"
    echo "    connect p95:  $p95"
    echo "    peak memory:  ${peak_mem} MiB"
    echo "    peak cpu:     ${peak_cpu}%"
    echo "    mem early:    ${early_peak} MiB  (first ${DRIFT_WINDOW_SEC}s)"
    echo "    mem late:     ${late_peak} MiB  (last ${DRIFT_WINDOW_SEC}s)"
    echo "    mem drift:    ${mem_drift} MiB"
    echo "    ws_errors/s:  ${ws_err_per_sec}"

    echo "    k6:"
    parse_k6_summary "$k6_out"

    local conns; conns=$(parse_conns "$srv_out"); conns="${conns:-0}"

    printf '%s\n' "$tp"             >> "/tmp/wsca_${lang}_${scenario}_tp"
    printf '%s\n' "$p95"            >> "/tmp/wsca_${lang}_${scenario}_p95"
    printf '%s\n' "$peak_mem"       >> "/tmp/wsca_${lang}_${scenario}_mem_peak"
    printf '%s\n' "$peak_cpu"       >> "/tmp/wsca_${lang}_${scenario}_cpu_peak"
    printf '%s\n' "$early_peak"     >> "/tmp/wsca_${lang}_${scenario}_mem_early_peak"
    printf '%s\n' "$late_peak"      >> "/tmp/wsca_${lang}_${scenario}_mem_late_peak"
    printf '%s\n' "$mem_drift"      >> "/tmp/wsca_${lang}_${scenario}_mem_drift"
    printf '%s\n' "$ws_err_per_sec" >> "/tmp/wsca_${lang}_${scenario}_err_rate"
    printf '%s\n' "$conns"          >> "/tmp/wsca_${lang}_${scenario}_conns"
}

run_language_soak() {
    local lang=$1

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $lang"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    echo ""
    echo "  [1/2] steady-soak  — 100 VUs × 1 msg/s × 300s"
    configure_server_args "$lang" "$STEADY_SOAK_SRV_SEC"
    run_scenario_soak "$lang" steady-soak "$STEADY_SOAK_SRV_SEC" "${soak_args[@]}"

    echo ""
    echo "  [2/2] churn-soak   — 200 VUs × connect→2s→leave × 180s"
    configure_server_args "$lang" "$CHURN_SOAK_SRV_SEC"
    run_scenario_soak "$lang" churn-soak "$CHURN_SOAK_SRV_SEC" "${soak_args[@]}"

    echo ""
}

format_stat() {
    awk '{sum+=$1; sumsq+=$1*$1; n++} END {
        if(n>1) {
            mean=sum/n;
            stdev=sqrt((sumsq/n) - (mean*mean));
            printf "%.1f±%.1f", mean, stdev
        } else if (n==1) {
            printf "%.2f", $1
        } else {
            printf "N/A"
        }
    }' "$1" 2>/dev/null || echo "N/A"
}

format_stat_int() {
    awk '{sum+=$1; n++} END {
        if(n>=1) { printf "%.0f", sum/n }
        else     { printf "N/A" }
    }' "$1" 2>/dev/null || echo "N/A"
}

print_summary_table() {
    echo "╔══════════════════════════════════════════════════════════════════════════════════════════════╗"
    echo "║               Profile A — Soak Results Summary                                               ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    printf "%-8s  %16s  %14s  %10s  %10s  %10s  %12s\n" \
        "Language" "Steady-soak tp" "Churn connects" "Mem early" "Mem late" "Mem drift" "ws_err/s"
    printf "%-8s  %16s  %14s  %10s  %10s  %10s  %12s\n" \
        "────────" "────────────────" "──────────────" "──────────" "──────────" "──────────" "────────────"

    for lang in "${LANGUAGES[@]}"; do
        st=$(format_stat     "/tmp/wsca_${lang}_steady-soak_tp")
        conns=$(format_stat_int "/tmp/wsca_${lang}_churn-soak_conns")
        mem_e=$(format_stat_int "/tmp/wsca_${lang}_steady-soak_mem_early_peak")
        mem_l=$(format_stat_int "/tmp/wsca_${lang}_steady-soak_mem_late_peak")
        drift=$(format_stat_int "/tmp/wsca_${lang}_steady-soak_mem_drift")
        err=$(format_stat    "/tmp/wsca_${lang}_steady-soak_err_rate")

        mem_e_str="${mem_e} MiB"; [ "$mem_e" = "N/A" ] && mem_e_str="N/A"
        mem_l_str="${mem_l} MiB"; [ "$mem_l" = "N/A" ] && mem_l_str="N/A"
        drift_str="${drift} MiB"; [ "$drift" = "N/A" ] && drift_str="N/A"

        printf "%-8s  %16s  %14s  %10s  %10s  %10s  %12s\n" \
            "$lang" "$st msg/s" "$conns" "$mem_e_str" "$mem_l_str" "$drift_str" "$err /s"
    done
}

# ── banner ─────────────────────────────────────────────────────────────────

echo "╔═════════════════════════════════════════════════╗"
echo "║  WebSocket Public Chat — Profile A Soak         ║"
echo "║  Framework: GoFiber / Axum / zap                ║"
echo "║  Steady-soak (300s) / Churn-soak (180s)         ║"
echo "║  KPIs: memory drift, error accumulation         ║"
echo "╚═════════════════════════════════════════════════╝"
echo "Date: $(date)"
echo ""
echo "Estimated runtime: ~$(( (STEADY_SOAK_SRV_SEC + CHURN_SOAK_SRV_SEC) * ${#LANGUAGES[@]} / 60 + 5 )) min"
echo ""

require_docker
ensure_network

# ── build ──────────────────────────────────────────────────────────────────

echo "Building images..."
for lang in "${LANGUAGES[@]}"; do
    build_image "$lang"
done

printf "  %-6s" "k6:"
if docker build -q -t wsc-k6 "$K6_DIR" >/dev/null 2>&1; then echo " ✓"; else echo " ✗"; die "k6 build failed"; fi
echo ""

# ── run benchmark ──────────────────────────────────────────────────────────

rm -f /tmp/wsca_*_steady-soak_* /tmp/wsca_*_churn-soak_*

BENCH_RUNS=${BENCH_RUNS:-1}

for run in $(seq 1 "$BENCH_RUNS"); do
    if [ "$BENCH_RUNS" -gt 1 ]; then
        echo "Run $run/$BENCH_RUNS"
    fi
    for lang in "${LANGUAGES[@]}"; do
        run_language_soak "$lang"
    done
done

# ── summary table ──────────────────────────────────────────────────────────

print_summary_table
rm -f /tmp/wsca_*_steady-soak_* /tmp/wsca_*_churn-soak_*

echo ""
echo "Results saved to: $RESULT_FILE"

cp "$RESULT_FILE" "$RESULT_LATEST_FILE"

echo "Latest soak profile A: $RESULT_LATEST_FILE"
