# Parquet File Reader: Go vs Rust vs Zig

โปรเจกต์นี้ทำ Parquet-subset reader สำหรับ benchmark งาน decode `RLE/bit-packing hybrid` พร้อม parse footer metadata length และ magic bytes (`PAR1`) แบบ streaming-oriented decode loop

## วัตถุประสงค์
- ฝึก parse โครงสร้างไฟล์แบบ Parquet subset (header/footer/metadata length)
- ฝึก decode RLE + bit-packing hybrid encoding
- เปรียบเทียบประสิทธิภาพ decode loop ระหว่าง Go/Rust/Zig

## โครงสร้าง

```text
parquet-file-reader/
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
│   └── sample.parquet
├── benchmark/
│   ├── results/
│   └── run.sh
└── README.md
```

## Dependencies
- Docker
- Python 3 (generate test parquet-subset file)

## Build & Run

### Generate test data

```bash
python3 test-data/generate.py
```

### Go

```bash
unset GOROOT && go build -o ../bin/parquet-file-reader-go .
../bin/parquet-file-reader-go ../test-data/sample.parquet 40
```

### Rust

```bash
cargo build --release
./target/release/parquet-file-reader ../test-data/sample.parquet 40
```

### Zig

```bash
zig build -Doptimize=ReleaseFast
./zig-out/bin/parquet-file-reader ../test-data/sample.parquet 40
```

## Benchmark

```bash
bash benchmark/run.sh
```

ผลลัพธ์จะถูก save อัตโนมัติลง `benchmark/results/parquet-file-reader_YYYYMMDD_HHMMSS.txt`

(benchmark รัน 5 ครั้ง: 1 warm-up + 4 measured ผ่าน Docker)

## Benchmark Results

```text
╔══════════════════════════════════════════╗
║      Parquet File Reader Benchmark       ║
╚══════════════════════════════════════════╝
  Input    : test-data/sample.parquet
  Repeats  : 40
  Mode     : Docker

── Go   ───────────────────────────────────────
  Run 1 (warm-up): 73ms
  Run 2           : 140ms
  Run 3           : 63ms
  Run 4           : 71ms
  Run 5           : 67ms
  Avg: 85ms  |  Min: 63ms  |  Max: 140ms

  Total processed: 8000000
  Processing time: 0.067s
  Average latency: 0.000008ms
  Throughput     : 119200832.92 items/sec

── Rust ───────────────────────────────────────
  Run 1 (warm-up): 48ms
  Run 2           : 48ms
  Run 3           : 51ms
  Run 4           : 69ms
  Run 5           : 56ms
  Avg: 56ms  |  Min: 48ms  |  Max: 69ms

  Total processed: 8000000
  Processing time: 0.056s
  Average latency: 0.000007ms
  Throughput     : 143730004.91 items/sec

── Zig  ───────────────────────────────────────
  Run 1 (warm-up): 56ms
  Run 2           : 70ms
  Run 3           : 66ms
  Run 4           : 56ms
  Run 5           : 57ms
  Avg: 62ms  |  Min: 56ms  |  Max: 70ms

  Total processed: 8000000
  Processing time: 0.057s
  Average latency: 0.000007ms
  Throughput     : 140448513.55 items/sec

── Binary Size ───────────────────────────────
  Go  : 1.6MB
  Rust: 388KB
  Zig : 2.2MB

── Code Lines ────────────────────────────────
  Go  : 177 lines
  Rust: 186 lines
  Zig : 159 lines
```

ผลลัพธ์ถูกบันทึกไว้ที่:
`benchmark/results/parquet-file-reader_20260226_231756.txt`

### Summary

## ตารางเปรียบเทียบ

| Metric | Go | Rust | Zig |
|--------|----|------|-----|
| Avg time (4 measured runs) | 85ms | **56ms** | 62ms |
| Min/Max time | 63/140ms | **48/69ms** | 56/70ms |
| Total processed | 8,000,000 | 8,000,000 | 8,000,000 |
| Throughput | 119,200,832.92 items/sec | **143,730,004.91 items/sec** | 140,448,513.55 items/sec |
| Average latency | 0.000008ms | **0.000007ms** | 0.000007ms |
| Binary size | 1.6MB | **388KB** | 2.2MB |

**Key insight**: สำหรับงาน decode RLE/bit-packing subset นี้ Rust ให้ throughput สูงสุดเล็กน้อย ขณะที่ Zig ใกล้เคียงมาก และ Rust ยังได้ binary size เล็กที่สุด.
