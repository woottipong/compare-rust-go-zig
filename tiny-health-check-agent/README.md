# Tiny Health Check Agent

จำลอง health-check agent สำหรับตรวจสถานะ service หลายตัวจาก input CSV แล้วประเมิน policy แบบ fail/recover streak + cooldown เพื่อเปรียบเทียบประสิทธิภาพของ Go / Rust / Zig

## วัตถุประสงค์

- วัด **health-check throughput** ในงาน loop ประเภท sidecar agent
- เปรียบเทียบ **stateful policy evaluation** (streak + cooldown arrays ต่อ target)
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
│   ├── generate.py     # generates targets.csv (5,000 rows)
│   └── targets.csv
├── benchmark/
│   └── run.sh
└── README.md
```

## Policy Algorithm

สำหรับ target แต่ละตัวในแต่ละ loop iteration:

```
seed = (iteration+1)*31 + (idx+1)*17
latency = base_ms + (seed % (jitter_ms + 1))
flap    = seed % 97 == 0
is_up   = expected_up XOR flap

if latency > 0 AND NOT is_up:
    fail_streak[idx]++
    recover_streak[idx] = 0
else:
    recover_streak[idx]++
    fail_streak[idx] = 0

if fail_streak[idx] >= 3 AND cooldown[idx] == 0:
    → fire FAIL alert, set cooldown = 8

if recover_streak[idx] >= 2 AND cooldown[idx] == 0:
    → fire RECOVER alert
```

`Total processed = checks_run + alerts_fired`

## Test Data

ไฟล์ `test-data/targets.csv` — 5,000 rows (168.9 KB):

```csv
# id,name,expected_up,base_ms,jitter_ms
1,auth-svc-0001,true,22,8
2,payment-handler-0002,false,80,30
```

| Field | Description |
|-------|-------------|
| `id` | ลำดับ 1–5000 |
| `name` | ชื่อ service เช่น `auth-service-0001` |
| `expected_up` | สถานะปกติ: `true` (87.5%) / `false` (12.5%) |
| `base_ms` | latency พื้นฐาน (5–200 ms) |
| `jitter_ms` | jitter สูงสุด (1–50 ms) |

สร้างใหม่ได้ด้วย `python3 test-data/generate.py`

## Build & Run

```bash
docker build -t hca-go go/
docker build -t hca-rust rust/
docker build -t hca-zig zig/

docker run --rm -v "$PWD/test-data:/data:ro" hca-go
docker run --rm -v "$PWD/test-data:/data:ro" hca-rust
docker run --rm -v "$PWD/test-data:/data:ro" hca-zig

# custom loops
docker run --rm -v "$PWD/test-data:/data:ro" hca-go /data/targets.csv 150000
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

## Benchmark

```bash
bash benchmark/run.sh
```

รัน 5 ครั้งต่อภาษา: 1 warm-up + 4 measured พร้อมสรุป Avg/Min/Max และ binary size

ผลลัพธ์จะถูกบันทึกอัตโนมัติที่ `benchmark/results/tiny_health_check_agent_<timestamp>.txt`

## Benchmark Results

วัดด้วย `LOOPS=150000` บน 5,000 targets (750M checks/run, Docker-based, Apple M-series)

```text
╔════════════════════════════════╗
║ Tiny Health Check Agent Bench  ║
╚════════════════════════════════╝

─ Go ─────────────────────
  Warm-up: 505082017.22 checks/sec
  Run 1: 504338254.05 checks/sec
  Run 2: 505876671.03 checks/sec
  Run 3: 495663731.26 checks/sec
  Run 4: 505155099.68 checks/sec
  Avg: 502758439.00 checks/sec
  Min: 495663731 checks/sec
  Max: 505876671 checks/sec

─ Rust ─────────────────────
  Warm-up: 572056676.45 checks/sec
  Run 1: 527646984.11 checks/sec
  Run 2: 556941165.81 checks/sec
  Run 3: 566444852.12 checks/sec
  Run 4: 566015155.49 checks/sec
  Avg: 554262039.38 checks/sec
  Min: 527646984 checks/sec
  Max: 566444852 checks/sec

─ Zig ─────────────────────
  Warm-up: 644663755.43 checks/sec
  Run 1: 645812742.83 checks/sec
  Run 2: 642661541.01 checks/sec
  Run 3: 642803686.42 checks/sec
  Run 4: 641727014.70 checks/sec
  Avg: 643251246.24 checks/sec
  Min: 641727015 checks/sec
  Max: 645812743 checks/sec

─ Binary Size ───────────────
  Go: 1.50MB
  Rust: 388.00KB
  Zig: 2.21MB
```

| Metric | Go | Rust | Zig |
|--------|----|------|-----|
| Throughput (avg) | 502,758,439 checks/sec | 554,262,039 checks/sec | **643,251,246 checks/sec** |
| Throughput (min) | 495,663,731 checks/sec | 527,646,984 checks/sec | **641,727,015 checks/sec** |
| Throughput (max) | 505,876,671 checks/sec | 566,444,852 checks/sec | **645,812,743 checks/sec** |
| Variance | 2.0% | 7.0% | **0.6%** |
| Binary Size | 1.50MB | **388KB** | 2.21MB |

## Key Insights

1. **Zig ชนะ throughput** ที่ 643M checks/sec — เร็วกว่า Rust 16%, เร็วกว่า Go 28%
2. **Zig มี variance ต่ำที่สุด** (0.6%) เพราะ ReleaseFast + deterministic code layout ให้ผลคงที่
3. **Rust ชนะ binary size** ที่ 388KB (เล็กกว่า Go 3.9×, เล็กกว่า Zig 5.7×) เหมาะกับ sidecar
4. **ทุกภาษาวัดได้ ~4–6 cycles/check** ที่ 3GHz ซึ่งแสดงว่า state arrays (120KB) fit ใน L2 cache
5. **Benchmark stability**: เปลี่ยนจาก 12 targets + LOOPS=350,000 (≈80ms/run, variance 25–29%) เป็น 5,000 targets + LOOPS=150,000 (≈2.5s/run, variance 0.6–7%) — ผลลัพธ์น่าเชื่อถือมากขึ้น

## Technical Notes

- **Go**: `make([]int, len(targets))` สำหรับ streak/cooldown arrays — GC ไม่มีผลในระหว่าง hot loop เพราะไม่มี allocation ใน `runChecks()`
- **Rust**: `vec![0usize; targets.len()]` + `saturating_sub(1)` สำหรับ cooldown decrement — branchless
- **Zig**: `allocator.alloc(usize, targets.len)` + `@memset(0)` — ใช้ GPA allocator สำหรับ init เท่านั้น, hot loop ไม่มี allocation
