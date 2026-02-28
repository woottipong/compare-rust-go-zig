# Task 8.2: Benchmark Script — Multi-run (3x) + randomize order + stdev

## Status
[DONE]

## Description
ปัจจุบันรัน benchmark แค่ 1 ครั้ง และเรียงลำดับ go → rust → zig ทุกครั้ง ทำให้:
1. ไม่มี statistical confidence — ค่าที่เห็นอาจเป็น noise จาก Docker scheduling
2. ภาษาแรก (Go) อาจได้ warm-cache advantage

เพิ่ม:
- **Multi-run mode**: รัน 3 รอบ แล้วคำนวณ mean/stdev
- **Randomize order**: สลับลำดับภาษาทุกรอบ
- **Summary with stdev**: แสดงค่าเฉลี่ย ± standard deviation

## Acceptance Criteria
- [x] env var `BENCH_RUNS=3` (default 1 เพื่อ backward compat)
- [x] เมื่อ BENCH_RUNS>1 ลำดับภาษาถูก shuffle ทุกรอบ
- [x] Summary table แสดง mean ± stdev เมื่อ BENCH_RUNS>1
- [x] ผลแต่ละรอบยังเก็บแยกไฟล์ปกติ
- [x] BENCH_RUNS=1 ทำงานเหมือนเดิมทุกประการ

## Tests Required
- manual: รัน `BENCH_RUNS=2 bash benchmark/run-profile-b.sh` verify 2 รอบ + summary

## Dependencies
- Task 8.1 (CPU sampling + resource limits)

## Files Affected
- `benchmark/run-profile-a.sh`
- `benchmark/run-profile-b.sh`

## Implementation Notes

### Shuffle function
```bash
shuffle_array() {
    local -a arr=("$@")
    local n=${#arr[@]}
    for ((i = n - 1; i > 0; i--)); do
        j=$((RANDOM % (i + 1)))
        local tmp="${arr[$i]}"
        arr[$i]="${arr[$j]}"
        arr[$j]="$tmp"
    done
    echo "${arr[@]}"
}
```

### Multi-run loop
```bash
BENCH_RUNS=${BENCH_RUNS:-1}

for run in $(seq 1 "$BENCH_RUNS"); do
    if [ "$BENCH_RUNS" -gt 1 ]; then
        IFS=' ' read -ra LANG_ORDER <<< "$(shuffle_array "${LANGUAGES[@]}")"
        echo "Run $run/$BENCH_RUNS — order: ${LANG_ORDER[*]}"
    else
        LANG_ORDER=("${LANGUAGES[@]}")
    fi
    for lang in "${LANG_ORDER[@]}"; do
        run_language_scenarios "$lang"
    done
done
```

### Stdev calculation (awk)
```bash
# จากไฟล์ /tmp/wsc_${lang}_${scenario}_tp_run${run}
awk '{sum+=$1; sumsq+=$1*$1; n++} END {
    mean=sum/n;
    stdev=sqrt(sumsq/n - mean*mean);
    printf "%.2f ± %.2f", mean, stdev
}'
```
