# Tiny Health Check Agent

จำลอง health-check agent สำหรับตรวจสถานะ service หลายตัวจาก input CSV แล้วประเมิน policy แบบ fail/recover streak + cooldown เพื่อเปรียบเทียบประสิทธิภาพของ Go / Rust / Zig

## วัตถุประสงค์

- วัด **health-check throughput** ในงาน loop ประเภท sidecar agent
- เปรียบเทียบ **policy evaluation** ที่มี state ต่อ target (streak/cooldown)
- วัด **binary size** สำหรับแนวคิด zero-dependency runtime

## Directory Structure

```text
tiny-health-check-agent/
├── go/
│   ├── main.go
│   ├── go.mod
│   └── Dockerfile
├── rust/
│   ├── src/main.rs
│   ├── Cargo.toml
│   └── Dockerfile
├── zig/
│   ├── src/main.zig
│   ├── build.zig
│   ├── build.zig.zon
│   └── Dockerfile
├── test-data/
│   └── targets.csv
├── benchmark/
│   └── run.sh
└── README.md
```

## Input Format

ไฟล์ `test-data/targets.csv`:

```csv
id,name,expected_up,base_ms,jitter_ms
1,auth-service,true,22,8
2,payments-service,true,35,12
```

## Statistics Output Format

ทั้ง 3 ภาษาแสดงผลรูปแบบเดียวกัน:

```text
--- Statistics ---
Total processed: <N>
Processing time: <X.XXX>s
Average latency: <X.XXX>ms
Throughput: <X.XX> checks/sec
```

## Build & Run

### Docker build

```bash
docker build -t hca-go go/
docker build -t hca-rust rust/
docker build -t hca-zig zig/
```

### Run

```bash
docker run --rm -v "$PWD/test-data:/data:ro" hca-go
docker run --rm -v "$PWD/test-data:/data:ro" hca-rust
docker run --rm -v "$PWD/test-data:/data:ro" hca-zig

# custom loops
docker run --rm -v "$PWD/test-data:/data:ro" hca-go /data/targets.csv 350000
```

## Benchmark

```bash
bash benchmark/run.sh
```

ผลลัพธ์จะถูกบันทึกอัตโนมัติที่ `benchmark/results/tiny_health_check_agent_<timestamp>.txt`

รัน 5 ครั้งต่อภาษา: 1 warm-up + 4 measured พร้อมสรุป Avg/Min/Max และ binary size

## Benchmark Results

วัดด้วย `LOOPS=350000` บน 12 targets (Docker-based, Apple M-series)

```text
╔════════════════════════════════╗
║ Tiny Health Check Agent Bench  ║
╚════════════════════════════════╝

─ Go ─────────────────────
  Warm-up: 399576547.93 checks/sec
  Run 1: 363147494.23 checks/sec
  Run 2: 350346013.69 checks/sec
  Run 3: 420135831.57 checks/sec
  Run 4: 439259710.97 checks/sec
  Avg: 393222262.61 checks/sec
  Min: 350346014 checks/sec
  Max: 439259711 checks/sec

─ Rust ─────────────────────
  Warm-up: 620763465.50 checks/sec
  Run 1: 584189126.54 checks/sec
  Run 2: 454394491.78 checks/sec
  Run 3: 530104145.73 checks/sec
  Run 4: 479280072.39 checks/sec
  Avg: 511991959.11 checks/sec
  Min: 454394492 checks/sec
  Max: 584189127 checks/sec

─ Zig ─────────────────────
  Warm-up: 612857900.66 checks/sec
  Run 1: 636664685.53 checks/sec
  Run 2: 671405142.89 checks/sec
  Run 3: 630178413.70 checks/sec
  Run 4: 690908182.85 checks/sec
  Avg: 657289106.24 checks/sec
  Min: 630178414 checks/sec
  Max: 690908183 checks/sec

─ Binary Size ───────────────
  Go: 1.50MB
  Rust: 388.00KB
  Zig: 2.21MB
```

| Metric | Go | Rust | Zig |
|--------|----|------|-----|
| Throughput (avg) | 393,222,263 checks/sec | 511,991,959 checks/sec | **657,289,106 checks/sec** |
| Throughput (min) | 350,346,014 checks/sec | 454,394,492 checks/sec | **630,178,414 checks/sec** |
| Throughput (max) | 439,259,711 checks/sec | 584,189,127 checks/sec | **690,908,183 checks/sec** |
| Binary Size | 1.50MB | **388KB** | 2.21MB |

### Summary

## Key Insight

1. **Zig ชนะ throughput เฉลี่ย** ที่ ~657M checks/sec (~28.4% เร็วกว่า Rust, ~67.1% เร็วกว่า Go)
2. **Rust ชนะ binary size** ชัดเจนที่ 388KB เหมาะกับการทำ sidecar footprint ต่ำ
3. **Zig ชนะทั้ง floor และ peak throughput** ในรอบล่าสุด (min/max สูงสุด)
