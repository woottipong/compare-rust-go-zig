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
├── test-data -> ../test-data  # symlink ไปยัง shared test-data
├── benchmark/          # Scripts สำหรับ benchmark
└── README.md           # คำแนะนำ build/run + ตาราง comparison
```

> **Shared test-data**: ไฟล์วิดีโอเก็บที่ `<repo-root>/test-data/` ใช้ร่วมกันทุก project ผ่าน symlink

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

### สร้าง Test Video (shared)
```bash
cd <repo-root>/test-data
ffmpeg -f lavfi -i testsrc=duration=30:size=640x360:rate=30 -pix_fmt yuv420p sample.mp4
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
| **Performance** | 1452ms avg | 1395ms avg | **1380ms avg** |
| **Peak Memory** | 20MB | 18MB | **16MB** |
| **Binary Size** | 2.6MB | 467KB | **288KB** |
| **Code Lines** | 324 | 274 | **266** |

## ผลการวัด (Benchmark Results)

```
╔══════════════════════════════════════════╗
║      HLS Stream Segmenter Benchmark       ║
╚══════════════════════════════════════════╝
  Input    : test-data/sample.mp4 (30s, 640x360, H.264)
  Segment  : 5s → 6 segments
  Runs     : 5 (1 warm-up)

── Go     ─────────────────────────────────────
  Run 1 (warm-up): 1625ms (6 segments)
  Run 2           : 1510ms (6 segments)
  Run 3           : 1535ms (6 segments)
  Run 4           : 1386ms (6 segments)
  Run 5           : 1379ms (6 segments)
  ─────────────────────────────────────────
  Avg: 1452ms  |  Min: 1379ms  |  Max: 1535ms
  Peak Memory: 20336 KB

── Rust   ─────────────────────────────────────
  Run 1 (warm-up): 1550ms (6 segments)
  Run 2           : 1366ms (6 segments)
  Run 3           : 1486ms (6 segments)
  Run 4           : 1368ms (6 segments)
  Run 5           : 1361ms (6 segments)
  ─────────────────────────────────────────
  Avg: 1395ms  |  Min: 1361ms  |  Max: 1486ms
  Peak Memory: 18912 KB

── Zig    ─────────────────────────────────────
  Run 1 (warm-up): 1379ms (6 segments)
  Run 2           : 1364ms (6 segments)
  Run 3           : 1393ms (6 segments)
  Run 4           : 1378ms (6 segments)
  Run 5           : 1388ms (6 segments)
  ─────────────────────────────────────────
  Avg: 1380ms  |  Min: 1364ms  |  Max: 1393ms
  Peak Memory: 16672 KB

── Binary Size ───────────────────────────────
  Go  : 2.6M
  Rust: 467K
  Zig : 288K

── Code Lines ────────────────────────────────
  Go  : 324 lines
  Rust: 274 lines
  Zig : 266 lines
```

## หมายเหตุ
- **Go/Rust/Zig**: ทุกภาษาใช้เวลาใกล้เคียงกัน ~1.4s → I/O ของการ write raw YUV frame data เป็น bottleneck หลัก
- **Zig**: Binary เล็กที่สุด (288KB), memory น้อยที่สุด (16MB), variance ต่ำที่สุด
- **Rust**: Memory ต่ำกว่า Go เพราะไม่มี GC overhead
- **HLS**: สร้าง .m3u8 playlist และ .ts segments ที่มี raw YUV420P frame data
- **Double-pointer in Go CGO**: `*(**C.AVStream)` pattern สำหรับ access C array
- **Persistent file handle**: key fix — ต้องเปิดไฟล์ segment ค้างไว้ระหว่าง frames ไม่ใช่เปิด/ปิดทุก frame
