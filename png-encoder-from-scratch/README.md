# PNG Encoder from Scratch: Go vs Rust vs Zig

โปรเจกต์นี้ implement PNG encoder แบบไม่พึ่ง libpng โดยอ่านไฟล์ PPM (P6) แล้ว encode เป็น PNG ด้วยโครงสร้าง chunk + zlib/deflate (stored block)

## วัตถุประสงค์
- ฝึก bit/byte-level file format handling (PNG signature, chunk, CRC32)
- ฝึกการประกอบ zlib stream + DEFLATE stored block
- เปรียบเทียบ performance งาน encode แบบ pure algorithm ระหว่าง Go/Rust/Zig

## โครงสร้าง

```text
png-encoder-from-scratch/
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
│   └── sample.ppm
├── benchmark/
│   ├── results/
│   └── run.sh
└── README.md
```

## Dependencies
- Docker
- Python 3 (generate test image)

## Build & Run

### Generate test data

```bash
python3 test-data/generate.py
```

### Go

```bash
unset GOROOT && go build -o ../bin/png-encoder-go .
../bin/png-encoder-go ../test-data/sample.ppm ../test-data/output_go.png 30
```

### Rust

```bash
cargo build --release
./target/release/png-encoder ../test-data/sample.ppm ../test-data/output_rust.png 30
```

### Zig

```bash
zig build -Doptimize=ReleaseFast
./zig-out/bin/png-encoder ../test-data/sample.ppm ../test-data/output_zig.png 30
```

## Benchmark

```bash
bash benchmark/run.sh
```

ผลลัพธ์จะถูก save อัตโนมัติลง `benchmark/results/png-encoder-from-scratch_YYYYMMDD_HHMMSS.txt`

(benchmark รัน 5 ครั้ง: 1 warm-up + 4 measured ผ่าน Docker)

## Benchmark Results

```text
╔══════════════════════════════════════════╗
║   PNG Encoder From Scratch Benchmark     ║
╚══════════════════════════════════════════╝
  Input    : test-data/sample.ppm
  Repeats  : 30
  Mode     : Docker

── Go   ───────────────────────────────────────
  Run 1 (warm-up): 130ms
  Run 2           : 117ms
  Run 3           : 126ms
  Run 4           : 120ms
  Run 5           : 135ms
  Avg: 124ms  |  Min: 117ms  |  Max: 135ms

  Total processed: 7864320
  Processing time: 0.135s
  Average latency: 0.000017ms
  Throughput     : 58142584.58 items/sec

── Rust ───────────────────────────────────────
  Run 1 (warm-up): 164ms
  Run 2           : 166ms
  Run 3           : 167ms
  Run 4           : 162ms
  Run 5           : 165ms
  Avg: 165ms  |  Min: 162ms  |  Max: 167ms

  Total processed: 7864320
  Processing time: 0.165s
  Average latency: 0.000021ms
  Throughput     : 47791195.30 items/sec

── Zig  ───────────────────────────────────────
  Run 1 (warm-up): 287ms
  Run 2           : 289ms
  Run 3           : 300ms
  Run 4           : 304ms
  Run 5           : 293ms
  Avg: 296ms  |  Min: 289ms  |  Max: 304ms

  Total processed: 7864320
  Processing time: 0.293s
  Average latency: 0.000037ms
  Throughput     : 26833474.37 items/sec

── Binary Size ───────────────────────────────
  Go  : 1.6MB
  Rust: 388KB
  Zig : 2.3MB

── Code Lines ────────────────────────────────
  Go  : 234 lines
  Rust: 248 lines
  Zig : 252 lines
```

ผลลัพธ์ถูกบันทึกไว้ที่:
`benchmark/results/png-encoder-from-scratch_20260226_224814.txt`

### Summary

## ตารางเปรียบเทียบ

| Metric | Go | Rust | Zig |
|--------|----|------|-----|
| Avg time (4 measured runs) | **124ms** | 165ms | 296ms |
| Min/Max time | **117/135ms** | 162/167ms | 289/304ms |
| Total processed | 7,864,320 | 7,864,320 | 7,864,320 |
| Throughput | **58,142,584.58 items/sec** | 47,791,195.30 items/sec | 26,833,474.37 items/sec |
| Average latency | **0.000017ms** | 0.000021ms | 0.000037ms |
| Binary size | 1.6MB | **388KB** | 2.3MB |

**Key insight**: สำหรับ implementation แบบ baseline (stored block + filter none) ในโจทย์นี้ Go ทำ throughput ได้สูงสุด ขณะที่ Rust ได้ binary size เล็กที่สุด.
