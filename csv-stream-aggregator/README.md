# CSV Stream Aggregator: Go vs Rust vs Zig

โปรเจกต์นี้ทำ streaming aggregation บนไฟล์ CSV ขนาดใหญ่ โดยคำนวณ `GROUP BY category` และ `SUM/COUNT` แบบ single-pass พร้อม benchmark เทียบ Go/Rust/Zig

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
../bin/csv-stream-aggregator-go ../test-data/sales.csv 150
```

### Rust

```bash
cargo build --release
./target/release/csv-stream-aggregator ../test-data/sales.csv 150
```

### Zig

```bash
zig build -Doptimize=ReleaseFast
./zig-out/bin/csv-stream-aggregator ../test-data/sales.csv 150
```

## Benchmark

```bash
bash benchmark/run.sh
```

ผลลัพธ์จะถูก save อัตโนมัติลง `benchmark/results/csv-stream-aggregator_YYYYMMDD_HHMMSS.txt`

(benchmark รัน 5 ครั้ง: 1 warm-up + 4 measured ผ่าน Docker)

## Benchmark Results

วัดด้วย `REPEATS=150` บน 200,000 rows (8 categories, 2.9MB CSV), Docker-based, Apple M-series

```text
╔══════════════════════════════════════════╗
║      CSV Stream Aggregator Benchmark     ║
╚══════════════════════════════════════════╝
  Input    : test-data/sales.csv
  Repeats  : 150
  Mode     : Docker

── Go   ───────────────────────────────────────
  Run 1 (warm-up): 4687ms
  Run 2           : 4660ms
  Run 3           : 4561ms
  Run 4           : 4688ms
  Run 5           : 4620ms
  ─────────────────────────────────────────
  Avg: 4632ms  |  Min: 4561ms  |  Max: 4688ms

  Total processed: 30000000
  Processing time: 4.620s
  Average latency: 0.000154ms
  Throughput     : 6494196.91 items/sec

── Rust ───────────────────────────────────────
  Run 1 (warm-up): 3481ms
  Run 2           : 3472ms
  Run 3           : 3470ms
  Run 4           : 3431ms
  Run 5           : 3454ms
  ─────────────────────────────────────────
  Avg: 3456ms  |  Min: 3431ms  |  Max: 3472ms

  Total processed: 30000000
  Processing time: 3.454s
  Average latency: 0.000115ms
  Throughput     : 8686598.49 items/sec

── Zig  ───────────────────────────────────────
  Run 1 (warm-up): 1157ms
  Run 2           : 1239ms
  Run 3           : 1171ms
  Run 4           : 1163ms
  Run 5           : 1141ms
  ─────────────────────────────────────────
  Avg: 1178ms  |  Min: 1141ms  |  Max: 1239ms

  Total processed: 30000000
  Processing time: 1.141s
  Average latency: 0.000038ms
  Throughput     : 26299551.23 items/sec

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
`benchmark/results/csv-stream-aggregator_20260227_014429.txt`

## ตารางเปรียบเทียบ

| Metric | Go | Rust | Zig |
|--------|----|------|-----|
| Avg time (4 measured runs) | 4,632ms | 3,456ms | **1,178ms** |
| Min/Max time | 4,561/4,688ms | 3,431/3,472ms | **1,141/1,239ms** |
| Total processed | 30,000,000 | 30,000,000 | 30,000,000 |
| Throughput | 6,494,196 items/sec | 8,686,598 items/sec | **26,299,551 items/sec** |
| Average latency | 0.000154ms | 0.000115ms | **0.000038ms** |
| Binary size | 1.5MB | **452KB** | 2.3MB |
| Code lines | 120 | 120 | **114** |

## Key Insights

1. **Zig ชนะ throughput อย่างชัดเจน** ที่ 26.3M items/sec — เร็วกว่า Rust 3.0×, เร็วกว่า Go 4.0×
2. **เหตุผลหลัก — I/O strategy ต่างกัน**:
   - **Zig**: `readFileAlloc()` → โหลดทั้งไฟล์เข้า memory ครั้งเดียว, `splitScalar('\n')` split in-place (no alloc per line)
   - **Rust**: `BufReader` + `.lines()` → string allocation ต่อบรรทัด ใช้ heap alloc ทุก line
   - **Go**: `bufio.Scanner` → string conversion ต่อบรรทัด + map lookup ด้วย string key
3. **Zig variance ต่ำมาก** (1,141–1,239ms, ~9%) ด้วย in-memory split ที่ไม่มี syscall overhead ใน loop
4. **Rust variance ต่ำที่สุด** (3,431–3,472ms, ~1%) สะท้อน BufReader ที่ predictable
5. **Rust ชนะ binary size** ที่ 452KB
6. **Go ใช้ code เท่า Rust** (120 บรรทัด) แต่ช้ากว่าเพราะ `strings.Split()` สร้าง slice allocation และ map ใช้ string hashing ที่หนักกว่า

## Technical Notes

- **CSV**: 200,000 rows × 2 columns (category, amount), 8 categories, ~14.5 bytes/row
- **Aggregation**: `GROUP BY category → SUM(amount), COUNT(*)` — ผลลัพธ์ 8 buckets
- **Total processed**: 200,000 rows × 150 repeats = 30,000,000 rows
- **Go**: `bufio.Scanner` + `strings.Split` + `map[string]aggregate` — all heap, GC pressure per line
- **Rust**: `BufReader` + `split(',')` + `HashMap<String, Aggregate>` — String alloc per line via `.entry().or_default()`
- **Zig**: `readFileAlloc` (full file load) + `splitScalar('\n')` (iterator, no alloc) + `StringHashMap` with `dupe` only for new keys — minimal allocations
