# Subtitle Burn-in Engine

เปรียบเทียบการทำ Subtitle Burn-in Engine ด้วย Go, Rust, และ Zig

## วัตถุประสงค์
ฝังไฟล์ SRT/VTT ลงในเนื้อวิดีโอและ re-encode (ฝึก Memory Safety, Pixel Manipulation, และ Re-encoding)

## โครงสร้างโปรเจกต์
```
subtitle-burn-in-engine/
├── go/                 # Go + CGO + FFmpeg + libass
├── rust/               # Rust + ffmpeg-sys-next 8.0 + libass-sys
├── zig/                # Zig + @cImport + FFmpeg + libass
├── test-data/          # ไฟล์วิดีโอและ subtitle สำหรับทดสอบ (gitignored)
├── benchmark/          # Scripts สำหรับ benchmark
└── README.md           # คำแนะนำ build/run + ตาราง comparison
```

## Dependencies

### FFmpeg + libass Development Libraries
```bash
# macOS
brew install ffmpeg libass

# Ubuntu/Debian
sudo apt-get install libavformat-dev libavcodec-dev libavutil-dev libswscale-dev libass-dev
```

## Build & Run

### Go
```bash
cd go
unset GOROOT
go mod init subtitle-burn-in-engine  # ครั้งแรกเท่านั้น
go build -o ../bin/burner-go .
../bin/burner-go test-data/video.mp4 test-data/subs.srt output.mp4
```

### Rust
```bash
cd rust
LLVM_CONFIG_PATH=/opt/homebrew/opt/llvm/bin/llvm-config \
LIBCLANG_PATH=/opt/homebrew/opt/llvm/lib \
PKG_CONFIG_PATH=/opt/homebrew/Cellar/ffmpeg/8.0.1_4/lib/pkgconfig \
cargo build --release
./target/release/subtitle-burn-in-engine test-data/video.mp4 test-data/subs.srt output.mp4
```

### Zig
```bash
cd zig
zig build -Doptimize=ReleaseFast
./zig-out/bin/subtitle-burn-in-engine test-data/video.mp4 test-data/subs.srt output.mp4
```

## Benchmark
```bash
cd subtitle-burn-in-engine
bash benchmark/run.sh
```

ผลลัพธ์จะถูก save อัตโนมัติลง `benchmark/results/subtitle-burn-in-engine_YYYYMMDD_HHMMSS.txt`

### สร้าง Test Data
```bash
cd subtitle-burn-in-engine/test-data

# สร้างวิดีโอ 30s
ffmpeg -f lavfi -i testsrc=duration=30:size=640x360:rate=25 -pix_fmt yuv420p video.mp4

# สร้าง subtitle ง่ายๆ
cat > subs.srt << 'EOF'
1
00:00:00,000 --> 00:00:03,000
Hello World!

2
00:00:03,000 --> 00:00:06,000
This is a test subtitle.

3
00:00:06,000 --> 00:00:09,000
Subtitle Burn-in Engine
EOF
```

## การเปรียบเทียบ

| Aspect | Go | Rust | Zig |
|--------|----|------|-----|
| **FFmpeg Integration** | CGO | ffmpeg-sys-next 8.0 | @cImport |
| **Subtitle Rendering** | libass CGO | libass-sys | @cImport |
| **Re-encoding** | libavcodec | libavcodec | libavcodec |
| **Memory Management** | GC + Manual (CGO) | Ownership + Drop trait | Manual |
| **Performance** | 1869ms avg* | 1625ms avg* | **1350ms avg*** |
| **Binary Size** | 1.6MB | 1.6MB | **2.3MB** |
| **Code Lines** | 340 | **230** | 332 |

> *Docker overhead included. Zig เร็วที่สุด, Rust กระชับ, Go code ยาวที่สุด

## หมายเหตุ
- **Go**: `golang:1.25-bookworm` + `debian:bookworm-slim`, CGO memory management ซับซ้อนกับ libass + FFmpeg
- **Rust**: `libass-sys` + `scopeguard`, bookworm runtime, binary เล็กเท่า Go (1.6MB)
- **Zig**: `@cImport` สำหรับ FFmpeg + libass, bookworm runtime — เร็วสุด variance ต่ำสุด
- **Re-encoding**: decode → burn subtitle → encode กลับ — FFmpeg encode เป็น bottleneck
- **Docker overhead**: ตัวเลข ~1.3-1.9s รวม container startup และ FFmpeg init

## สรุปผล
- **Zig** เร็วสุด (1350ms avg) และ variance ต่ำสุด
- **Rust** เร็วกว่า Go (~13% เร็วกว่า) และ code กระชับสุด (230 lines)
- **Go** ช้าสุดแต่ code อ่านง่าย
- Binary size ใกล้เคียงกันทุกภาษา (1.6-2.3MB) เพราะ FFmpeg shared libs ครอบงำ
- FFmpeg decode+encode เป็น bottleneck หลัก — language overhead แทบไม่ต่างกัน
