# Video Frame Extractor

เปรียบเทียบการทำ Video Frame Extractor ด้วย Go, Rust, และ Zig

## วัตถุประสงค์
ดึงภาพ Thumbnail จากวิดีโอในช่วงเวลาที่กำหนด (ฝึก C Interop กับ FFmpeg)

## โครงสร้างโปรเจกต์
```
video-frame-extractor/
├── go/                 # Go + CGO + FFmpeg C API
├── rust/               # Rust + ffmpeg-sys-next 8.0
├── zig/                # Zig + @cImport + FFmpeg
├── test-data/          # ไฟล์วิดีโอสำหรับทดสอบ (gitignored)
├── bin/                # compiled binaries
└── benchmark/          # Scripts สำหรับ benchmark
```

## การติดตั้ง Dependencies

### FFmpeg Development Libraries
```bash
# macOS
brew install ffmpeg

# Ubuntu/Debian
sudo apt-get install libavformat-dev libavcodec-dev libavutil-dev libswscale-dev
```

### สร้าง Test Video
```bash
cd video-frame-extractor/test-data
ffmpeg -f lavfi -i testsrc=duration=30:size=640x360:rate=25 -pix_fmt yuv420p sample.mp4
```

## Build & Run

### Go
```bash
cd go
unset GOROOT
go mod init video-frame-extractor  # ครั้งแรกเท่านั้น
go build -o ../bin/extractor-go .
../bin/extractor-go ../test-data/sample.mp4 5.0 ../output_go.ppm
```

### Rust
```bash
cd rust
LLVM_CONFIG_PATH=/opt/homebrew/opt/llvm/bin/llvm-config \
LIBCLANG_PATH=/opt/homebrew/opt/llvm/lib \
PKG_CONFIG_PATH=/opt/homebrew/Cellar/ffmpeg/8.0.1_4/lib/pkgconfig \
cargo build --release
./target/release/video-frame-extractor ../test-data/sample.mp4 5.0 ../output_rust.ppm
```

### Zig
```bash
cd zig
zig build -Doptimize=ReleaseFast
./zig-out/bin/video-frame-extractor ../test-data/sample.mp4 5.0 ../output_zig.ppm
```

## Docker Build & Run

### Build Images
```bash
# Build all images
docker build -t vfe-go   go/
docker build -t vfe-rust rust/
docker build -t vfe-zig  zig/

# Run with test data
docker run --rm -v "$(pwd)/test-data:/data:ro" vfe-go /data/sample.mp4 5.0 /data/output.ppm
docker run --rm -v "$(pwd)/test-data:/data:ro" vfe-rust /data/sample.mp4 5.0 /data/output.ppm
docker run --rm -v "$(pwd)/test-data:/data:ro" vfe-zig /data/sample.mp4 5.0 /data/output.ppm
```

### Docker Run (Interactive)
```bash
# Go
docker run --rm -v "$(pwd)/test-data:/data:ro" -v "$(pwd)/output:/out" vfe-go \
  /data/sample.mp4 5.0 /out/output_go.ppm

# Rust
docker run --rm -v "$(pwd)/test-data:/data:ro" -v "$(pwd)/output:/out" vfe-rust \
  /data/sample.mp4 5.0 /out/output_rust.ppm

# Zig
docker run --rm -v "$(pwd)/test-data:/data:ro" -v "$(pwd)/output:/out" vfe-zig \
  /data/sample.mp4 5.0 /out/output_zig.ppm
```

## Benchmark
```bash
cd video-frame-extractor
bash benchmark/run.sh
```

ผลลัพธ์จะถูก save อัตโนมัติลง `benchmark/results/video-frame-extractor_YYYYMMDD_HHMMSS.txt`

### Summary

## การเปรียบเทียบ

| Aspect | Go | Rust | Zig |
|--------|----|------|-----|
| **C Interop** | CGO | ffmpeg-sys-next 8.0 | @cImport |
| **Memory Safety** | GC + Manual (CGO) | Ownership + scopeguard | Manual |
| **Binary Size** | 1.6MB | **388KB** | 1.4MB |
| **Performance** | 517ms avg* | **545ms avg*** | 583ms avg* |
| **Code Lines** | 182 | 192 | **169** |
| **Build Time** | Fast | Medium (env vars) | Fast |

> *Docker container overhead included (~400-500ms startup). ทุกภาษาเร็วใกล้เคียงกัน — FFmpeg I/O เป็น bottleneck

## Benchmark Results

```
╔══════════════════════════════════════════╗
║    Video Frame Extractor Benchmark       ║
╚══════════════════════════════════════════╝
  Input    : test-data/sample.mp4
  Timestamp: 5.0s
  Runs     : 5 (1 warm-up)
  Mode     : Docker

── Go   ───────────────────────────────────────
  Run 1 (warm-up): 660ms
  Run 2           : 479ms
  Run 3           : 499ms
  Run 4           : 460ms
  Run 5           : 632ms
  ─────────────────────────────────────────
  Avg: 517ms  |  Min: 460ms  |  Max: 632ms

── Rust ───────────────────────────────────────
  Run 1 (warm-up): 1037ms
  Run 2           : 628ms
  Run 3           : 514ms
  Run 4           : 520ms
  Run 5           : 521ms
  ─────────────────────────────────────────
  Avg: 545ms  |  Min: 514ms  |  Max: 628ms

── Zig  ───────────────────────────────────────
  Run 1 (warm-up): 627ms
  Run 2           : 499ms
  Run 3           : 571ms
  Run 4           : 756ms
  Run 5           : 507ms
  ─────────────────────────────────────────
  Avg: 583ms  |  Min: 499ms  |  Max: 756ms

── Binary Size ───────────────────────────────
  Go  : 1.6MB
  Rust: 388KB
  Zig : 1.4MB

── Code Lines ────────────────────────────────
  Go  : 182 lines
  Rust: 192 lines
  Zig : 169 lines
```

**Key insight:** การดึงเฟรมเดียวจากวิดีโอถูกครอบงำด้วย FFmpeg decode path และ container startup จึงทำให้ตัวเลข 3 ภาษาใกล้กันมาก; ความต่างหลักในงานนี้จึงไปอยู่ที่ binary size/maintainability มากกว่าความเร็ว runtime ล้วน.

## หมายเหตุ
- **Go**: `golang:1.25-bookworm` + `debian:bookworm-slim` — ใช้ C helper wrapper แทน `*C.SwsContext` field โดยตรง
- **Rust**: `ffmpeg-sys-next 8.0` รองรับ FFmpeg 8.x, ใช้ `scopeguard::guard()` สำหรับ RAII
- **Zig**: Manual memory management แต่มี control สูง
- **Docker overhead**: ตัวเลข benchmark รวม container startup (~400ms) ทำให้สูงกว่า native run (~50ms)
