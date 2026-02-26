# SQLite Query Engine: Go vs Rust vs Zig

โปรเจกต์นี้ benchmark การ query SQLite แบบอ่าน raw B-tree page (ไม่ใช้ sqlite client library) เพื่อเปรียบเทียบประสิทธิภาพการสแกนข้อมูลระหว่าง Go, Rust, Zig

## วัตถุประสงค์
- ฝึก parsing SQLite file format (varint, record header, table B-tree)
- เปรียบเทียบ throughput ของการ scan/filter (`cpu_pct > 80.0`)
- วัด binary size และ code size ของแต่ละภาษา

## โครงสร้าง

```text
sqlite-query-engine/
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
│   └── Dockerfile
├── test-data/
│   ├── generate.py
│   └── metrics.db
├── benchmark/
│   ├── results/
│   └── run.sh
└── README.md
```

## Dependencies
- Docker
- Python 3 (สำหรับ generate test database)

## Build & Run

### Generate test data

```bash
python3 test-data/generate.py
```

### Go

```bash
unset GOROOT && go build -o ../bin/sqlite-query-engine-go .
../bin/sqlite-query-engine-go ../test-data/metrics.db 1000
```

### Rust

```bash
cargo build --release
./target/release/sqlite-query-engine ../test-data/metrics.db 1000
```

### Zig

```bash
zig build -Doptimize=ReleaseFast
./zig-out/bin/sqlite-query-engine ../test-data/metrics.db 1000
```

## Benchmark

```bash
bash benchmark/run.sh
```

ผลลัพธ์จะถูก save อัตโนมัติลง `benchmark/results/sqlite-query-engine_YYYYMMDD_HHMMSS.txt`

(benchmark รัน 5 ครั้ง: 1 warm-up + 4 measured ผ่าน Docker)

## Benchmark Results

```text
╔══════════════════════════════════════════╗
║      SQLite Query Engine Benchmark       ║
╚══════════════════════════════════════════╝
  Input    : test-data/metrics.db
  Repeats  : 1000
  Mode     : Docker

── Go   ───────────────────────────────────────
  Run 1 (warm-up): 707ms
  Run 2           : 704ms
  Run 3           : 710ms
  Run 4           : 715ms
  Run 5           : 707ms
  Avg: 709ms  |  Min: 704ms  |  Max: 715ms

  Total processed: 200000000
  Processing time: 0.707s
  Average latency: 0.000004ms
  Throughput     : 282688841.90 items/sec

── Rust ───────────────────────────────────────
  Run 1 (warm-up): 563ms
  Run 2           : 568ms
  Run 3           : 564ms
  Run 4           : 564ms
  Run 5           : 558ms
  Avg: 563ms  |  Min: 558ms  |  Max: 568ms

  Total processed: 200000000
  Processing time: 0.558s
  Average latency: 0.000003ms
  Throughput     : 358383573.39 items/sec

── Zig  ───────────────────────────────────────
  Run 1 (warm-up): 229ms
  Run 2           : 228ms
  Run 3           : 235ms
  Run 4           : 221ms
  Run 5           : 223ms
  Avg: 226ms  |  Min: 221ms  |  Max: 235ms

  Total processed: 200000000
  Processing time: 0.223s
  Average latency: 0.000001ms
  Throughput     : 897198107.73 items/sec

── Binary Size ───────────────────────────────
  Go  : 1.6MB
  Rust: 388KB
  Zig : 2.2MB

── Code Lines ────────────────────────────────
  Go  : 310 lines
  Rust: 342 lines
  Zig : 285 lines
```

ผลลัพธ์ถูกบันทึกไว้ที่:
`benchmark/results/sqlite-query-engine_20260226_224046.txt`

### Summary

## ตารางเปรียบเทียบ

| Metric | Go | Rust | Zig |
|--------|----|------|-----|
| Avg time (4 measured runs) | 709ms | 563ms | **226ms** |
| Min/Max time | 704/715ms | 558/568ms | **221/235ms** |
| Total processed | 200,000,000 | 200,000,000 | 200,000,000 |
| Throughput | 282,688,841.90 items/sec | 358,383,573.39 items/sec | **897,198,107.73 items/sec** |
| Average latency | 0.000004ms | 0.000003ms | **0.000001ms** |
| Binary size | 1.6MB | **388KB** | 2.2MB |

**Key insight**: Zig ชนะด้าน raw scan throughput อย่างชัดเจนในโจทย์ parsing/query แบบ CPU-bound นี้ ขณะที่ Rust ได้ binary เล็กที่สุด และ Go ยังเด่นด้านความอ่านง่ายของ implementation.
