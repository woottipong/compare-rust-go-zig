# JPEG Thumbnail Pipeline: Go vs Rust vs Zig

โปรเจกต์นี้สร้าง thumbnail จากไฟล์ JPEG โดยเรียก pipeline `decode -> resize (bilinear) -> encode` ผ่าน FFmpeg และ benchmark orchestration ของ Go/Rust/Zig แบบเทียบกันใน Docker

## วัตถุประสงค์
- ฝึก pipeline แปลงภาพ JPEG เป็น thumbnail
- เปรียบเทียบ overhead ของแต่ละภาษาในการเรียกงานซ้ำหลายรอบ
- วัด processing time, throughput, binary size, code lines

## โครงสร้าง

```text
jpeg-thumbnail-pipeline/
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
- FFmpeg (สำหรับ generate test data ในเครื่อง)

## Build & Run

### Generate test image

```bash
bash test-data/generate.sh
```

### Go

```bash
unset GOROOT && go build -o ../bin/jpeg-thumbnail-go .
../bin/jpeg-thumbnail-go ../test-data/sample.jpg ../test-data/out_go.jpg 160 90 20
```

### Rust

```bash
cargo build --release
./target/release/jpeg-thumbnail ../test-data/sample.jpg ../test-data/out_rust.jpg 160 90 20
```

### Zig

```bash
zig build -Doptimize=ReleaseFast
./zig-out/bin/jpeg-thumbnail ../test-data/sample.jpg ../test-data/out_zig.jpg 160 90 20
```

## Benchmark

```bash
bash benchmark/run.sh
```

ผลลัพธ์จะถูก save อัตโนมัติลง `benchmark/results/jpeg-thumbnail-pipeline_YYYYMMDD_HHMMSS.txt`

(benchmark รัน 5 ครั้ง: 1 warm-up + 4 measured ผ่าน Docker)

## Benchmark Results

```text
╔══════════════════════════════════════════╗
║    JPEG Thumbnail Pipeline Benchmark     ║
╚══════════════════════════════════════════╝
  Input    : test-data/sample.jpg
  Resize   : 160x90
  Repeats  : 20
  Mode     : Docker

── Go   ───────────────────────────────────────
  Run 1 (warm-up): 1545ms
  Run 2           : 1295ms
  Run 3           : 1259ms
  Run 4           : 1284ms
  Run 5           : 1219ms
  Avg: 1264ms  |  Min: 1219ms  |  Max: 1295ms

  Total processed: 288000
  Processing time: 1.219s
  Average latency: 0.004233ms
  Throughput     : 236263.22 items/sec

── Rust ───────────────────────────────────────
  Run 1 (warm-up): 1233ms
  Run 2           : 1264ms
  Run 3           : 1237ms
  Run 4           : 1226ms
  Run 5           : 1254ms
  Avg: 1245ms  |  Min: 1226ms  |  Max: 1264ms

  Total processed: 288000
  Processing time: 1.254s
  Average latency: 0.004354ms
  Throughput     : 229690.39 items/sec

── Zig  ───────────────────────────────────────
  Run 1 (warm-up): 1238ms
  Run 2           : 1227ms
  Run 3           : 1211ms
  Run 4           : 1217ms
  Run 5           : 1308ms
  Avg: 1240ms  |  Min: 1211ms  |  Max: 1308ms

  Total processed: 288000
  Processing time: 1.308s
  Average latency: 0.004541ms
  Throughput     : 220197.58 items/sec

── Binary Size ───────────────────────────────
  Go  : 1.8MB
  Rust: 452KB
  Zig : 2.3MB

── Code Lines ────────────────────────────────
  Go  : 106 lines
  Rust: 128 lines
  Zig : 102 lines
```

ผลลัพธ์ถูกบันทึกไว้ที่:
`benchmark/results/jpeg-thumbnail-pipeline_20260226_225459.txt`

### Summary

## ตารางเปรียบเทียบ

| Metric | Go | Rust | Zig |
|--------|----|------|-----|
| Avg time (4 measured runs) | 1264ms | 1245ms | **1240ms** |
| Min/Max time | 1219/1295ms | 1226/1264ms | **1211/1308ms** |
| Total processed | 288,000 | 288,000 | 288,000 |
| Throughput | **236,263.22 items/sec** | 229,690.39 items/sec | 220,197.58 items/sec |
| Average latency | **0.004233ms** | 0.004354ms | 0.004541ms |
| Binary size | 1.8MB | **452KB** | 2.3MB |

**Key insight**: เนื่องจากงานถูกครอบงำด้วยการเรียก FFmpeg ในแต่ละรอบ ทำให้เวลาของทั้ง 3 ภาษาใกล้กันมาก โดย Go มี throughput สูงสุดเล็กน้อย และ Rust ได้ binary size เล็กที่สุด.
