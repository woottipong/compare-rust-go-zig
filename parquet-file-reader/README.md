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
../bin/parquet-file-reader-go ../test-data/sample.parquet 1500
```

### Rust

```bash
cargo build --release
./target/release/parquet-file-reader ../test-data/sample.parquet 1500
```

### Zig

```bash
zig build -Doptimize=ReleaseFast
./zig-out/bin/parquet-file-reader ../test-data/sample.parquet 1500
```

## Benchmark

```bash
bash benchmark/run.sh
```

ผลลัพธ์จะถูก save อัตโนมัติลง `benchmark/results/parquet-file-reader_YYYYMMDD_HHMMSS.txt`

(benchmark รัน 5 ครั้ง: 1 warm-up + 4 measured ผ่าน Docker)

## Benchmark Results

วัดด้วย `REPEATS=1500` บน 200,000 values (bit_width=6, RLE+bitpack hybrid, 117KB), Docker-based, Apple M-series

```text
╔══════════════════════════════════════════╗
║      Parquet File Reader Benchmark       ║
╚══════════════════════════════════════════╝
  Input    : test-data/sample.parquet
  Repeats  : 1500
  Mode     : Docker

── Go   ───────────────────────────────────────
  Run 1 (warm-up): 2196ms
  Run 2           : 2185ms
  Run 3           : 2397ms
  Run 4           : 2588ms
  Run 5           : 2253ms
  ─────────────────────────────────────────
  Avg: 2355ms  |  Min: 2185ms  |  Max: 2588ms

  Total processed: 300000000
  Processing time: 2.253s
  Average latency: 0.000008ms
  Throughput     : 133143399.30 items/sec

── Rust ───────────────────────────────────────
  Run 1 (warm-up): 1643ms
  Run 2           : 1546ms
  Run 3           : 1522ms
  Run 4           : 1526ms
  Run 5           : 1559ms
  ─────────────────────────────────────────
  Avg: 1538ms  |  Min: 1522ms  |  Max: 1559ms

  Total processed: 300000000
  Processing time: 1.559s
  Average latency: 0.000005ms
  Throughput     : 192463333.58 items/sec

── Zig  ───────────────────────────────────────
  Run 1 (warm-up): 1872ms
  Run 2           : 1803ms
  Run 3           : 1786ms
  Run 4           : 1746ms
  Run 5           : 1749ms
  ─────────────────────────────────────────
  Avg: 1771ms  |  Min: 1746ms  |  Max: 1803ms

  Total processed: 300000000
  Processing time: 1.749s
  Average latency: 0.000006ms
  Throughput     : 171570407.02 items/sec

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
`benchmark/results/parquet-file-reader_20260227_014957.txt`

## ตารางเปรียบเทียบ

| Metric | Go | Rust | Zig |
|--------|----|------|-----|
| Avg time (4 measured runs) | 2,355ms | **1,538ms** | 1,771ms |
| Min/Max time | 2,185/2,588ms | **1,522/1,559ms** | 1,746/1,803ms |
| Total processed | 300,000,000 | 300,000,000 | 300,000,000 |
| Throughput | 133,143,399 items/sec | **192,463,333 items/sec** | 171,570,407 items/sec |
| Average latency | 0.000008ms | **0.000005ms** | 0.000006ms |
| Binary size | 1.6MB | **388KB** | 2.2MB |
| Code lines | 177 | 186 | **159** |

## Key Insights

1. **Rust ชนะ throughput** ที่ 192M items/sec — เร็วกว่า Zig 1.12×, เร็วกว่า Go 1.45× ในงาน RLE/bit-pack decode
2. **Rust มี variance ต่ำที่สุด** (1,522–1,559ms, ~2%) — LLVM auto-vectorization ให้ผลคงที่มาก
3. **Zig ตามมาที่ 2** (171M items/sec, ~3% variance) — ReleaseFast ให้ผลดีแต่ GPA allocator มีผลต่อ decode buffer alloc/free
4. **Go มี variance สูงสุด** (2,185–2,588ms, ~18%) จาก GC pause ในการจัดการ `values []uint32` slice ที่ grow ต่อรอบ
5. **Rust ชนะ binary size** ที่ 388KB เหมือนเดิม (เล็กกว่า Go 4.1×, เล็กกว่า Zig 5.7×)
6. **Zig ชนะ code lines** ที่ 159 บรรทัด — decode loop compact กว่าทั้ง Go และ Rust

## Technical Notes

- **File format**: `PAR1` magic + 1 byte bit_width + 4 bytes num_values + 4 bytes encoded_len + RLE/bitpack payload + JSON metadata + 4 bytes meta_len + `PAR1` magic
- **Decode pattern**: varint-prefixed header → even = RLE run (repeat v for N times), odd = bit-pack group (8 values × bit_width bits)
- **Hot path**: varint decode → branch RLE/bitpack → unpack bits (N×bit_width bit manipulations per group)
- **Total processed**: 200,000 values × 1,500 repeats = 300,000,000 decoded integers
- **Go**: `append(values, v)` per decoded value → slice grows + GC pressure; `decodeHybrid` returns new `[]uint32` every call
- **Rust**: `Vec::with_capacity(expected)` pre-allocates; `push()` within capacity = no realloc; LLVM optimizes bit manipulation tightly
- **Zig**: `ArrayList` with GPA alloc per iteration (alloc + free each `processFile`) — slightly heavier than Rust's pre-alloc approach
