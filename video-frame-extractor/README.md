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
├── test-data -> ../test-data  # symlink ไปยัง shared test-data
├── bin/                # compiled binaries
└── benchmark/          # Scripts สำหรับ benchmark
```

> **Shared test-data**: ไฟล์วิดีโอเก็บที่ `<repo-root>/test-data/` ใช้ร่วมกันทุก project ผ่าน symlink

## การติดตั้ง Dependencies

### FFmpeg Development Libraries
```bash
# macOS
brew install ffmpeg

# Ubuntu/Debian
sudo apt-get install libavformat-dev libavcodec-dev libavutil-dev libswscale-dev
```

### สร้าง Test Video (shared)
```bash
cd <repo-root>/test-data
ffmpeg -f lavfi -i testsrc=duration=30:size=1280x720:rate=30 -pix_fmt yuv420p sample.mp4
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

## Benchmark
```bash
cd benchmark
./run.sh ../test-data/sample.mp4 5.0

# Save results with timestamp
./results/save-results.sh video-frame-extractor
```

### ผลการวัดที่เก็บไว้
- **Full results**: `benchmark/results/video-frame-extractor_YYYYMMDD_HHMMSS.txt`
- **Summary CSV**: `benchmark/results/video-frame-extractor_summary.csv`
- ทุกครั้งที่รัน benchmark ควร save results เพื่อ tracking performance ข้ามเวลา

## การเปรียบเทียบ

| Aspect | Go | Rust | Zig |
|--------|----|------|-----|
| **C Interop** | CGO | ffmpeg-sys-next 8.0 | @cImport |
| **Memory Safety** | GC + Manual (CGO) | Ownership + scopeguard | Manual |
| **Binary Size** | 2.7MB | 451KB | **271KB** |
| **Performance** | **50ms avg** | 76ms avg | 51ms avg |
| **Memory Usage** | 20MB peak | 19MB peak | **19MB peak** |
| **Code Lines** | 182 | 192 | **169** |
| **Build Time** | Fast | Medium (env vars) | Fast |

## ผลการวัด (Benchmark Results)

```
╔══════════════════════════════════════════╗
║    Video Frame Extractor Benchmark       ║
╚══════════════════════════════════════════╝
  Input    : test-data/sample.mp4 (30s, 640x360, H.264)
  Timestamp: 5.0s
  Runs     : 5 (1 warm-up)

── Go     ─────────────────────────────────────
  Run 1 (warm-up): 513ms
  Run 2           : 50ms
  Run 3           : 50ms
  Run 4           : 51ms
  Run 5           : 50ms
  ─────────────────────────────────────────
  Avg: 50ms  |  Min: 50ms  |  Max: 51ms
  Peak Memory: 20224 KB

── Rust   ─────────────────────────────────────
  Run 1 (warm-up): 497ms
  Run 2           : 52ms
  Run 3           : 58ms
  Run 4           : 53ms
  Run 5           : 141ms
  ─────────────────────────────────────────
  Avg: 76ms  |  Min: 52ms  |  Max: 141ms
  Peak Memory: 19856 KB

── Zig    ─────────────────────────────────────
  Run 1 (warm-up): 53ms
  Run 2           : 51ms
  Run 3           : 51ms
  Run 4           : 51ms
  Run 5           : 54ms
  ─────────────────────────────────────────
  Avg: 51ms  |  Min: 51ms  |  Max: 54ms
  Peak Memory: 19632 KB

── Binary Size ───────────────────────────────
  Go  : 2.7M
  Rust: 451K
  Zig : 271K

── Code Lines ────────────────────────────────
  Go  : 182 lines
  Rust: 192 lines
  Zig : 169 lines
```

## หมายเหตุ
- **Go**: ต้อง `unset GOROOT` บนเครื่องที่มีหลาย Go versions, CGO memory leak ง่าย
- **Rust**: `ffmpeg-sys-next 8.0` รองรับ FFmpeg 8.x, ใช้ `scopeguard::guard()` สำหรับ RAII
- **Zig**: Manual memory management แต่มี control สูง, binary เล็กที่สุด (10x เล็กกว่า Go)
- **Performance**: ทุกภาษาใช้เวลาใกล้เคียงกัน ~50ms → FFmpeg operations เป็น bottleneck หลัก
