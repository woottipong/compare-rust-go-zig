# Task 8.1: Benchmark Script — เพิ่ม CPU sampling + pin resources

## Status
[TODO]

## Description
ปัจจุบัน benchmark script ไม่ได้:
1. วัด CPU usage ระหว่างทดสอบ
2. จำกัด resources ของ container (CPU/memory) ทำให้ผลอาจ noisy

เพิ่ม:
- **CPU sampling** ด้วย `docker stats` เก็บ peak CPU% เหมือน memory sampling ที่มีอยู่
- **Resource limits** ด้วย `--cpus 2 --memory 512m` เพื่อให้ทุกภาษาทดสอบบน resource เท่ากัน

**ต้องแก้ทั้ง run-profile-a.sh และ run-profile-b.sh**

## Acceptance Criteria
- [ ] Output ของแต่ละ scenario มี `peak cpu: X%` เพิ่มเข้ามา
- [ ] Summary table มีคอลัมน์ Peak CPU เพิ่ม
- [ ] Container ทุกตัวรันด้วย `--cpus 2 --memory 512m`
- [ ] Script ยังทำงานได้ปกติ (ไม่ break existing output format)

## Tests Required
- manual: รัน `bash benchmark/run-profile-b.sh` ให้ครบ 1 ภาษา verify output format

## Dependencies
- ไม่มี — standalone change

## Files Affected
- `benchmark/run-profile-a.sh`
- `benchmark/run-profile-b.sh`

## Implementation Notes

### CPU Sampling (เพิ่มใน run_scenario)
```bash
# เพิ่มถัดจาก memory sampling loop
cpu_file="/tmp/wsc_${lang}_${scenario}_cpu"
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
```

### Resource Limits (เพิ่มใน start_server)
```bash
docker run -d --network "$NETWORK" --name "$cname" \
    --cpus 2 --memory 512m \
    "$image" "$@" >/dev/null
```
