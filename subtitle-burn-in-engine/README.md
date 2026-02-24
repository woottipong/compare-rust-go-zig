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
cd benchmark
./run.sh test-data/video.mp4 test-data/subs.srt

# Save results with timestamp
./results/save-results.sh subtitle-burn-in-engine
```

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
| **Performance** | ~463ms avg | ~503ms avg | ~431ms avg |
| **Memory Usage** | 103,856 KB | 103,904 KB | 101,024 KB |
| **Binary Size** | 2.7MB | 1.6MB | 288KB |
| **Code Lines** | 340 | 230 | 332 |

## หมายเหตุ
- **Go**: CGO memory management ซับซ้อนกับ libass และ FFmpeg
- **Rust**: ใช้ `libass-sys` สำหรับ subtitle rendering, `scopeguard` สำหรับ cleanup
- **Zig**: ใช้ `@cImport` สำหรับทั้ง FFmpeg และ libass, manual memory management
- **Re-encoding**: ต้อง decode → burn subtitle → encode กลับ → ทำให้เห็น encode performance ครั้งแรก
- **Pixel Manipulation**: ต้อง blend subtitle pixels เข้ากับ video frames ด้วยมือ

## สรุปผล
- **Zig** เร็วสุดและ binary เล็กสุด (288KB) — เหมาะสำหรับ embedded/systems
- **Go** เร็วใกล้เคียง Zig (~7% ช้ากว่า) แต่ binary ใหญ่มาก (2.7MB) — เหมาะสำหรับ web services
- **Rust** ช้าสุดในชุดนี้ (~17% ช้ากว่า Zig) แต่ code กระชับสุด (230 lines) — เหมาะสำหรับ complex applications
- Memory ใกล้เคียงกันทุกภาษา (~100MB) เพราะ FFmpeg buffers ครอบงำ
- FFmpeg decode+encode เป็น bottleneck หลัก — language overhead แทบไม่ต่างกัน
