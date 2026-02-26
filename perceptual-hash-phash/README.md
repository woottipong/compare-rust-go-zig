# Perceptual Hash (pHash): Go vs Rust vs Zig

โปรเจกต์นี้คำนวณ pHash ของภาพ JPEG โดยทำขั้นตอน resize เป็น grayscale 32x32, คำนวณ DCT 2 มิติ, แล้วสร้าง 64-bit fingerprint จากค่า low-frequency block 8x8

## วัตถุประสงค์
- ฝึก math-heavy image fingerprinting (DCT-based)
- เปรียบเทียบ performance ของงานคำนวณล้วนระหว่าง Go/Rust/Zig
- วัด processing time, throughput, binary size, code lines

## โครงสร้าง

```text
perceptual-hash-phash/
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
│   ├── generate.sh
│   └── sample.jpg
├── benchmark/
│   ├── results/
│   └── run.sh
└── README.md
```

## Dependencies
- Docker
- FFmpeg (สำหรับ generate test image บนเครื่อง)

## Build & Run

### Generate test image

```bash
bash test-data/generate.sh
```

### Go

```bash
unset GOROOT && go build -o ../bin/phash-go .
../bin/phash-go ../test-data/sample.jpg 20
```

### Rust

```bash
cargo build --release
./target/release/phash ../test-data/sample.jpg 20
```

### Zig

```bash
zig build -Doptimize=ReleaseFast
./zig-out/bin/phash ../test-data/sample.jpg 20
```

## Benchmark

```bash
bash benchmark/run.sh
```

ผลลัพธ์จะถูก save อัตโนมัติลง `benchmark/results/perceptual-hash-phash_YYYYMMDD_HHMMSS.txt`

(benchmark รัน 5 ครั้ง: 1 warm-up + 4 measured ผ่าน Docker)

## ผลการวัด (Benchmark Results)

```text
╔══════════════════════════════════════════╗
║     Perceptual Hash (pHash) Benchmark    ║
╚══════════════════════════════════════════╝
  Input    : test-data/sample.jpg
  Repeats  : 20
  Mode     : Docker

── Go   ───────────────────────────────────────
  Run 1 (warm-up): 1539ms
  Run 2           : 1561ms
  Run 3           : 1677ms
  Run 4           : 1462ms
  Run 5           : 1566ms
  Avg: 1566ms  |  Min: 1462ms  |  Max: 1677ms

  Total processed: 20
  Processing time: 1.566s
  Average latency: 78.283256ms
  Throughput     : 12.77 items/sec

── Rust ───────────────────────────────────────
  Run 1 (warm-up): 1444ms
  Run 2           : 1364ms
  Run 3           : 1385ms
  Run 4           : 1371ms
  Run 5           : 1460ms
  Avg: 1395ms  |  Min: 1364ms  |  Max: 1460ms

  Total processed: 20
  Processing time: 1.460s
  Average latency: 72.990248ms
  Throughput     : 13.70 items/sec

── Zig  ───────────────────────────────────────
  Run 1 (warm-up): 1362ms
  Run 2           : 1560ms
  Run 3           : 1361ms
  Run 4           : 1346ms
  Run 5           : 1381ms
  Avg: 1412ms  |  Min: 1346ms  |  Max: 1560ms

  Total processed: 20
  Processing time: 1.381s
  Average latency: 69.046227ms
  Throughput     : 14.48 items/sec

── Binary Size ───────────────────────────────
  Go  : 1.8MB
  Rust: 452KB
  Zig : 2.3MB

── Code Lines ────────────────────────────────
  Go  : 205 lines
  Rust: 222 lines
  Zig : 185 lines
```

ผลลัพธ์ถูกบันทึกไว้ที่:
`benchmark/results/perceptual-hash-phash_20260226_230037.txt`

## ตารางเปรียบเทียบ

| Metric | Go | Rust | Zig |
|--------|----|------|-----|
| Avg time (4 measured runs) | 1566ms | **1395ms** | 1412ms |
| Min/Max time | 1462/1677ms | **1364/1460ms** | 1346/1560ms |
| Throughput | 12.77 items/sec | 13.70 items/sec | **14.48 items/sec** |
| Average latency | 78.283ms | 72.990ms | **69.046ms** |
| Binary size | 1.8MB | **452KB** | 2.3MB |

**Key insight**: งาน pHash รอบนี้ถูกครอบงำโดยการแปลงภาพด้วย FFmpeg + DCT ค่าค่อนข้างหนัก ทำให้ Zig และ Rust เร็วกว่า Go เล็กน้อย โดย Zig ได้ throughput สูงสุด และ Rust ได้ binary เล็กที่สุด.
