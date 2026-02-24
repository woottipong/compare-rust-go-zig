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
├── test-data/          # ไฟล์วิดีโอสำหรับทดสอบ
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
cd benchmark
./run.sh ../test-data/sample.mp4 10

# Save results with timestamp
./results/save-results.sh hls-stream-segmenter
```

### ผลการวัดที่เก็บไว้
- **Full results**: `benchmark/results/hls-stream-segmenter_YYYYMMDD_HHMMSS.txt`
- **Summary CSV**: `benchmark/results/hls-stream-segmenter_summary.csv`
- ทุกครั้งที่รัน benchmark ควร save results เพื่อ tracking performance ข้ามเวลา

## การเปรียบเทียบ

| Aspect | Go | Rust | Zig |
|--------|----|------|-----|
| **FFmpeg Integration** | CGO | ffmpeg-sys-next 8.0 | @cImport |
| **File I/O** | os package | std::fs | std.fs |
| **Memory Management** | GC + Manual (CGO) | Ownership + Drop trait | Manual |
| **Error Handling** | error interface | Result<T,E> | error union |
| **Performance** | **306ms avg** | 1012ms avg | 1014ms avg |
| **Peak Memory** | 25MB | 19MB | **17MB** |
| **Binary Size** | 2.6MB | 451KB | **288KB** |
| **Code Lines** | 290 | 256 | **239** |

## ผลการวัด (Benchmark Results)

```
╔══════════════════════════════════════════╗
║      HLS Stream Segmenter Benchmark       ║
╚══════════════════════════════════════════╝
  Input    : test-data/sample.mp4 (30s, 640x360, H.264)
  Segment  : 5s → 6 segments
  Runs     : 5 (1 warm-up)

── Go     ─────────────────────────────────────
  Avg: 306ms  |  Min: 282ms  |  Max: 333ms
  Peak Memory: 25216 KB

── Rust   ─────────────────────────────────────
  Avg: 1012ms  |  Min: 966ms  |  Max: 1071ms
  Peak Memory: 18944 KB

── Zig    ─────────────────────────────────────
  Avg: 1014ms  |  Min: 982ms  |  Max: 1056ms
  Peak Memory: 16672 KB

── Binary Size ───────────────────────────────
  Go  : 2.6M
  Rust: 451K
  Zig : 288K

── Code Lines ────────────────────────────────
  Go  : 290 lines
  Rust: 256 lines
  Zig : 239 lines
```

## หมายเหตุ
- **Go**: เร็วที่สุด (3x) เพราะ GC จัดการ memory โดยไม่ต้อง decode-encode ซ้ำ
- **Rust/Zig**: ช้ากว่าเพราะ write ทุก frame แยกไฟล์ (I/O bound) แต่ใช้ memory น้อยกว่า
- **Zig**: Binary เล็กที่สุด (288KB), memory น้อยที่สุด (17MB)
- **HLS**: ต้องสร้าง .m3u8 playlist และ .ts segments ตามมาตรฐาน Apple
- **Double-pointer in Go CGO**: `*(**C.AVStream)` pattern สำหรับ access C array
