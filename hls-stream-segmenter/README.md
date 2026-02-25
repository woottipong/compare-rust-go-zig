# HLS Stream Segmenter

เปรียบเทียบการทำ HLS Stream Segmenter ด้วย Go, Rust, และ Zig

## วัตถุประสงค์
ตัดวิดีโอเป็นชิ้นเล็กๆ (.ts) และสร้างไฟล์ .m3u8 สำหรับ HTTP Live Streaming (ฝึก File I/O และ Streaming)

## โครงสร้างโปรเจกต์
```
hls-stream-segmenter/
├── go/                 # Go + FFmpeg
├── rust/               # Rust + FFmpeg
├── zig/                # Zig + FFmpeg
├── test-data/          # ไฟล์วิดีโอสำหรับทดสอบ (gitignored)
├── benchmark/          # Scripts สำหรับ benchmark
└── README.md           # คำแนะนำ build/run + ตาราง comparison
```

## Dependencies

### FFmpeg Development Libraries
```bash
# macOS
brew install ffmpeg

# Ubuntu/Debian
sudo apt-get install libavformat-dev libavcodec-dev libavutil-dev libswscale-dev
```

## Build & Run

### Go
```bash
cd go
unset GOROOT
go mod init hls-stream-segmenter  # ครั้งแรกเท่านั้น
go build -o ../bin/segmenter-go .
../bin/segmenter-go ../test-data/sample.mp4 output_dir 10
```

### Rust
```bash
cd rust
LLVM_CONFIG_PATH=/opt/homebrew/opt/llvm/bin/llvm-config \
LIBCLANG_PATH=/opt/homebrew/opt/llvm/lib \
PKG_CONFIG_PATH=/opt/homebrew/Cellar/ffmpeg/8.0.1_4/lib/pkgconfig \
cargo build --release
./target/release/hls-stream-segmenter ../test-data/sample.mp4 output_dir 10
```

### Zig
```bash
cd zig
zig build -Doptimize=ReleaseFast
./zig-out/bin/hls-stream-segmenter ../test-data/sample.mp4 output_dir 10
```

## Benchmark
```bash
cd hls-stream-segmenter
bash benchmark/run.sh
```

ผลลัพธ์จะถูก save อัตโนมัติลง `benchmark/results/hls-stream-segmenter_YYYYMMDD_HHMMSS.txt`

### สร้าง Test Video
```bash
cd hls-stream-segmenter/test-data
ffmpeg -f lavfi -i testsrc=duration=30:size=640x360:rate=25 -pix_fmt yuv420p sample.mp4
```

## การเปรียบเทียบ

| Aspect | Go | Rust | Zig |
|--------|----|------|-----|
| **FFmpeg Integration** | CGO | ffmpeg-sys-next 8.0 | @cImport |
| **File I/O** | os package | std::fs | std.fs |
| **Memory Management** | GC + Manual (CGO) | Ownership + Drop trait | Manual |
| **Error Handling** | error interface | Result<T,E> | error union |
| **Performance** | 20874ms avg* | **16261ms avg*** | 15572ms avg* |
| **Binary Size** | 1.6MB | **388KB** | 1.5MB |
| **Code Lines** | 323 | 274 | **266** |

> *Docker + I/O overhead included. Go ช้ากว่า Rust/Zig ใน Docker เพราะ bookworm + glibc FFmpeg มี decode overhead สูงกว่า

## ผลการวัด (Benchmark Results)

```
╔══════════════════════════════════════════╗
║      HLS Stream Segmenter Benchmark       ║
╚══════════════════════════════════════════╝
  Input    : test-data/sample.mp4
  Segment  : 10s → 3 segments
  Runs     : 5 (1 warm-up)
  Mode     : Docker

── Go   ───────────────────────────────────────
  Run 1 (warm-up): 45863ms (3 segments)
  Run 2           : 18294ms (3 segments)
  Run 3           : 19651ms (3 segments)
  Run 4           : 20768ms (3 segments)
  Run 5           : 24784ms (3 segments)
  ─────────────────────────────────────────
  Avg: 20874ms  |  Min: 18294ms  |  Max: 24784ms

── Rust ───────────────────────────────────────
  Run 1 (warm-up): 17396ms (3 segments)
  Run 2           : 16418ms (3 segments)
  Run 3           : 15975ms (3 segments)
  Run 4           : 16505ms (3 segments)
  Run 5           : 16148ms (3 segments)
  ─────────────────────────────────────────
  Avg: 16261ms  |  Min: 15975ms  |  Max: 16505ms

── Zig  ───────────────────────────────────────
  Run 1 (warm-up): 15834ms (3 segments)
  Run 2           : 15136ms (3 segments)
  Run 3           : 15561ms (3 segments)
  Run 4           : 16401ms (3 segments)
  Run 5           : 15190ms (3 segments)
  ─────────────────────────────────────────
  Avg: 15572ms  |  Min: 15136ms  |  Max: 16401ms

── Binary Size ───────────────────────────────
  Go  : 1.6MB
  Rust: 388KB
  Zig : 1.5MB

── Code Lines ────────────────────────────────
  Go  : 323 lines
  Rust: 274 lines
  Zig : 266 lines
```

## หมายเหตุ
- **Go**: `golang:1.25-bookworm` + `debian:bookworm-slim` — ใช้ C helper wrapper (`hls_sws_scale`) เพื่อหลีกเลี่ยง `*C.SwsContext` field ใน struct ซึ่งไม่ทำงานบน bookworm arm64
- **Rust**: `ffmpeg-sys-next 8.0`, bookworm runtime — binary เล็กที่สุด (388KB)
- **Zig**: bookworm runtime, `@cImport` — performance ดีสุด, variance ต่ำสุด
- **HLS**: สร้าง .m3u8 playlist และ .ts segments ที่มี raw YUV420P frame data
- **I/O bound**: ทุกภาษาช้าใน Docker เพราะ FFmpeg decode + write segments เป็น I/O bottleneck
- **Persistent file handle**: ต้องเปิดไฟล์ segment ค้างไว้ระหว่าง frames ไม่ใช่เปิด/ปิดทุก frame
