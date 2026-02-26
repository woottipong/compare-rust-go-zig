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
../bin/jpeg-thumbnail-go ../test-data/sample.jpg ../test-data/out_go.jpg 160 90 50
```

### Rust

```bash
cargo build --release
./target/release/jpeg-thumbnail ../test-data/sample.jpg ../test-data/out_rust.jpg 160 90 50
```

### Zig

```bash
zig build -Doptimize=ReleaseFast
./zig-out/bin/jpeg-thumbnail ../test-data/sample.jpg ../test-data/out_zig.jpg 160 90 50
```

## Benchmark

```bash
bash benchmark/run.sh
```

ผลลัพธ์จะถูก save อัตโนมัติลง `benchmark/results/jpeg-thumbnail-pipeline_YYYYMMDD_HHMMSS.txt`

(benchmark รัน 5 ครั้ง: 1 warm-up + 4 measured ผ่าน Docker)

## Benchmark Results

วัดด้วย `REPEATS=50` บน 1280×720 JPEG → resize เป็น 160×90, Docker-based, Apple M-series

```text
╔══════════════════════════════════════════╗
║    JPEG Thumbnail Pipeline Benchmark     ║
╚══════════════════════════════════════════╝
  Input    : test-data/sample.jpg
  Resize   : 160x90
  Repeats  : 50
  Mode     : Docker

── Go   ───────────────────────────────────────
  Run 1 (warm-up): 2988ms
  Run 2           : 2819ms
  Run 3           : 2948ms
  Run 4           : 2863ms
  Run 5           : 2806ms
  ─────────────────────────────────────────
  Avg: 2859ms  |  Min: 2806ms  |  Max: 2948ms

  Total processed: 720000
  Processing time: 2.806s
  Average latency: 0.003897ms
  Throughput     : 256581.56 items/sec

── Rust ───────────────────────────────────────
  Run 1 (warm-up): 2920ms
  Run 2           : 3591ms
  Run 3           : 3014ms
  Run 4           : 3187ms
  Run 5           : 2830ms
  ─────────────────────────────────────────
  Avg: 3155ms  |  Min: 2830ms  |  Max: 3591ms

  Total processed: 720000
  Processing time: 2.830s
  Average latency: 0.003930ms
  Throughput     : 254421.98 items/sec

── Zig  ───────────────────────────────────────
  Run 1 (warm-up): 2873ms
  Run 2           : 3321ms
  Run 3           : 3091ms
  Run 4           : 3433ms
  Run 5           : 3056ms
  ─────────────────────────────────────────
  Avg: 3225ms  |  Min: 3056ms  |  Max: 3433ms

  Total processed: 720000
  Processing time: 3.056s
  Average latency: 0.004244ms
  Throughput     : 235600.41 items/sec

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
`benchmark/results/jpeg-thumbnail-pipeline_20260227_013702.txt`

## ตารางเปรียบเทียบ

| Metric | Go | Rust | Zig |
|--------|----|------|-----|
| Avg time (4 measured runs) | **2,859ms** | 3,155ms | 3,225ms |
| Min/Max time | **2,806/2,948ms** | 2,830/3,591ms | 3,056/3,433ms |
| Total processed | 720,000 | 720,000 | 720,000 |
| Throughput | **256,581 items/sec** | 254,421 items/sec | 235,600 items/sec |
| Average latency | **0.003897ms** | 0.003930ms | 0.004244ms |
| Binary size | 1.8MB | **452KB** | 2.3MB |
| Code lines | 106 | 128 | **102** |

## Key Insights

1. **ผลลัพธ์ทั้ง 3 ภาษาใกล้กันมาก** — Go 256K, Rust 254K, Zig 235K items/sec ต่างกันไม่ถึง 9% เพราะ bottleneck คือ ffmpeg subprocess ไม่ใช่ภาษา
2. **Go มี variance ต่ำที่สุด** (2,806–2,948ms, ~5%) เพราะ `os/exec` + goroutine scheduler ทำงานสม่ำเสมอ
3. **Rust มี variance สูง** (2,830–3,591ms, ~27%) — Docker CPU scheduling noise มีผลต่อ spawn + wait per call
4. **Zig ชนะ code lines** ที่ 102 บรรทัด — implementation เรียบง่ายที่สุด
5. **Rust ชนะ binary size** ที่ 452KB เหมือนเดิม
6. **งานนี้วัด orchestration overhead + ffmpeg JPEG pipeline** ไม่ใช่ language-level algorithm — เหมาะสำหรับเปรียบเทียบ process-spawn latency ของแต่ละภาษา

## Technical Notes

- **ffmpeg call**: `-f lavfi -i testsrc` → 1280×720 JPEG input; `scale=160:90:flags=bilinear` → 160×90 JPEG output
- **Timing scope**: timer ครอบ REPEATS × (fork + exec + wait) ไม่รวม file I/O load phase
- **Total processed**: 160 × 90 × 50 = 720,000 output pixels per Docker run
- **Go**: `os/exec.Command` → `CombinedOutput()` blocks until child exits
- **Rust**: `std::process::Command` → `.output()` blocks; stderr captured
- **Zig**: `std.process.Child` → `.spawn()` + `.wait()` pattern; stderr piped
