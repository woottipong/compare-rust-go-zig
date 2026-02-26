# CSV Stream Aggregator: Go vs Rust vs Zig

โปรเจกต์นี้ทำ streaming aggregation บนไฟล์ CSV ขนาดใหญ่ โดยคำนวณ `GROUP BY category` และ `SUM/COUNT` แบบไม่โหลดทั้งไฟล์เข้า memory พร้อม benchmark เทียบ Go/Rust/Zig

## วัตถุประสงค์
- ฝึก streaming I/O กับข้อมูลขนาดใหญ่
- เปรียบเทียบประสิทธิภาพงาน aggregation แบบ single-pass
- วัด processing time, throughput, binary size, code lines

## โครงสร้าง

```text
csv-stream-aggregator/
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
│   └── sales.csv
├── benchmark/
│   ├── results/
│   └── run.sh
└── README.md
```

## Dependencies
- Docker
- Python 3 (generate test CSV)

## Build & Run

### Generate test data

```bash
python3 test-data/generate.py
```

### Go

```bash
unset GOROOT && go build -o ../bin/csv-stream-aggregator-go .
../bin/csv-stream-aggregator-go ../test-data/sales.csv 30
```

### Rust

```bash
cargo build --release
./target/release/csv-stream-aggregator ../test-data/sales.csv 30
```

### Zig

```bash
zig build -Doptimize=ReleaseFast
./zig-out/bin/csv-stream-aggregator ../test-data/sales.csv 30
```

## Benchmark

```bash
bash benchmark/run.sh
```

ผลลัพธ์จะถูก save อัตโนมัติลง `benchmark/results/csv-stream-aggregator_YYYYMMDD_HHMMSS.txt`

(benchmark รัน 5 ครั้ง: 1 warm-up + 4 measured ผ่าน Docker)

## ผลการวัด (Benchmark Results)

```text
╔══════════════════════════════════════════╗
║      CSV Stream Aggregator Benchmark     ║
╚══════════════════════════════════════════╝
  Input    : test-data/sales.csv
  Repeats  : 30
  Mode     : Docker

── Go   ───────────────────────────────────────
  Run 1 (warm-up): 986ms
  Run 2           : 993ms
  Run 3           : 1004ms
  Run 4           : 1022ms
  Run 5           : 990ms
  Avg: 1002ms  |  Min: 990ms  |  Max: 1022ms

  Total processed: 6000000
  Processing time: 0.990s
  Average latency: 0.000165ms
  Throughput     : 6062818.63 items/sec

── Rust ───────────────────────────────────────
  Run 1 (warm-up): 795ms
  Run 2           : 742ms
  Run 3           : 746ms
  Run 4           : 793ms
  Run 5           : 750ms
  Avg: 757ms  |  Min: 742ms  |  Max: 793ms

  Total processed: 6000000
  Processing time: 0.750s
  Average latency: 0.000125ms
  Throughput     : 8003335.61 items/sec

── Zig  ───────────────────────────────────────
  Run 1 (warm-up): 265ms
  Run 2           : 255ms
  Run 3           : 255ms
  Run 4           : 259ms
  Run 5           : 259ms
  Avg: 257ms  |  Min: 255ms  |  Max: 259ms

  Total processed: 6000000
  Processing time: 0.259s
  Average latency: 0.000043ms
  Throughput     : 23183716.73 items/sec

── Binary Size ───────────────────────────────
  Go  : 1.5MB
  Rust: 452KB
  Zig : 2.3MB

── Code Lines ────────────────────────────────
  Go  : 120 lines
  Rust: 120 lines
  Zig : 114 lines
```

ผลลัพธ์ถูกบันทึกไว้ที่:
`benchmark/results/csv-stream-aggregator_20260226_231226.txt`

## ตารางเปรียบเทียบ

| Metric | Go | Rust | Zig |
|--------|----|------|-----|
| Avg time (4 measured runs) | 1002ms | 757ms | **257ms** |
| Min/Max time | 990/1022ms | 742/793ms | **255/259ms** |
| Total processed | 6,000,000 | 6,000,000 | 6,000,000 |
| Throughput | 6,062,818.63 items/sec | 8,003,335.61 items/sec | **23,183,716.73 items/sec** |
| Average latency | 0.000165ms | 0.000125ms | **0.000043ms** |
| Binary size | 1.5MB | **452KB** | 2.3MB |

**Key insight**: งาน streaming CSV aggregation รอบนี้ Zig ทำ throughput ได้สูงสุดอย่างชัดเจน ส่วน Rust อยู่ตรงกลางและได้ binary เล็กที่สุด.
