# Compare Rust / Go / Zig

เปรียบเทียบการเขียนโปรแกรมด้วย **Go**, **Rust**, และ **Zig** ผ่าน mini projects จริงๆ
เน้นวัดผล performance, binary size, memory usage, และ code complexity ในแต่ละโดเมน

---

## โครงสร้าง Repository

```
compare-rust-go-zig/
├── video-frame-extractor/    ✅ ดึง frame thumbnail จากวิดีโอ (FFmpeg C interop)
├── hls-stream-segmenter/     ✅ ตัดวิดีโอเป็น .ts + .m3u8 (HLS streaming)
├── <project-name>/           ⬜ projects ถัดไป
├── plan.md                   # รายการ projects ทั้งหมด + สถานะ
└── .windsurf/rules/          # Coding rules สำหรับแต่ละภาษา
    ├── go-dev.md
    ├── rust-dev.md
    ├── zig-dev.md
    └── project-structure.md
```

แต่ละ project มีโครงสร้างมาตรฐาน:

```
<project-name>/
├── go/          # Go + CGO หรือ net/http ฯลฯ
├── rust/        # Rust + relevant crates
├── zig/         # Zig + @cImport หรือ std
├── test-data/   # ไฟล์สำหรับทดสอบ (gitignored — generate เองด้วย ffmpeg)
├── benchmark/
│   ├── run.sh              # รัน benchmark ทั้ง 3 ภาษาพร้อมกัน
│   └── results/            # ผลลัพธ์ที่บันทึกไว้ (gitignored)
└── README.md
```

---

## ผลการเปรียบเทียบ (Completed Projects)

### 1. Video Frame Extractor
ดึง frame จากวิดีโอที่ตำแหน่ง timestamp ที่กำหนด → output PPM image

| Metric | Go | Rust | Zig |
|--------|-----|------|-----|
| **Avg Time** | **50ms** | 76ms | 51ms |
| **Peak Memory** | 20MB | 19MB | **19MB** |
| **Binary Size** | 2.7MB | 451KB | **271KB** |
| **Code Lines** | 182 | 192 | **169** |

**Key insight**: FFmpeg decode เป็น bottleneck → ทุกภาษาใช้เวลาใกล้เคียงกัน

### 2. HLS Stream Segmenter
ตัดวิดีโอ 30s เป็น 6 segments (5s each) → `.ts` + `playlist.m3u8`

| Metric | Go | Rust | Zig |
|--------|-----|------|-----|
| **Avg Time** | 1452ms | 1395ms | **1380ms** |
| **Peak Memory** | 20MB | 18MB | **16MB** |
| **Binary Size** | 2.6MB | 467KB | **288KB** |
| **Code Lines** | 324 | 274 | **266** |

**Key insight**: I/O ของการ write raw YUV420P frame เป็น bottleneck → ทุกภาษา ~1.4s

---

## Quick Start

### Prerequisites
```bash
# macOS
brew install ffmpeg llvm zig

# Ubuntu/Debian
sudo apt-get install libavformat-dev libavcodec-dev libavutil-dev libswscale-dev clang
```

### สร้าง Test Video
```bash
# ใน directory ของแต่ละ project
ffmpeg -f lavfi -i testsrc=duration=30:size=640x360:rate=25 -pix_fmt yuv420p test-data/sample.mp4
```

### Run Benchmark
```bash
cd <project-name>
bash benchmark/run.sh test-data/sample.mp4 [param]
```

---

## Build Commands

### Go
```bash
unset GOROOT && go build -o ../bin/<name>-go .
```

### Rust
```bash
LLVM_CONFIG_PATH=/opt/homebrew/opt/llvm/bin/llvm-config \
LIBCLANG_PATH=/opt/homebrew/opt/llvm/lib \
PKG_CONFIG_PATH=/opt/homebrew/Cellar/ffmpeg/8.0.1_4/lib/pkgconfig \
cargo build --release
```

### Zig
```bash
zig build -Doptimize=ReleaseFast
```

---

## สิ่งที่เรียนรู้

| ภาษา | จุดเด่น | จุดที่ต้องระวัง |
|------|---------|----------------|
| **Go** | เขียนง่าย, stdlib ครบ, build เร็ว | CGO memory leak ง่าย, binary ใหญ่ที่สุด |
| **Rust** | Memory safe, ไม่มี GC, `Option`/`Result` ชัดเจน | Build time นาน, env vars สำหรับ FFI |
| **Zig** | Binary เล็กที่สุด, C interop ตรง, `comptime` ทรงพลัง | Error handling verbose, ecosystem เล็ก |

---

## Lessons Learned

### video-frame-extractor
- FFmpeg 8.0: ใช้ `ffmpeg-sys-next = "8.0"` สำหรับ Rust (ไม่ใช่ `ffmpeg-next`)
- Zig 0.15+: ใช้ `createModule()` + `root_module` syntax ใน `build.zig`
- Go CGO: `*(**C.AVStream)` pattern สำหรับ access C pointer array
- Zig const pointer: ใช้ `@constCast` สำหรับ C functions ที่รับ non-const pointer

### hls-stream-segmenter
- **Critical**: ต้องเปิด segment file ค้างไว้ระหว่าง frames ไม่เปิด/ปิดทุก frame
- Zig: ใช้ `cwd().createFile()` ไม่ใช่ `createFileAbsolute()` สำหรับ relative paths
- Rust: `Option<File>` pattern สำหรับ conditional resource ownership
- Go: ไม่ต้อง `go mod init` ซ้ำถ้า `go.mod` มีอยู่แล้ว

---

## Projects ที่วางแผนไว้

ดูรายละเอียดทั้งหมดใน [`plan.md`](./plan.md) — มี 9 กลุ่ม 27 projects

กลุ่มใหม่ที่น่าสนใจ:
- **กลุ่ม 7**: Low-Level Networking (DNS Resolver, TCP Port Scanner, QUIC Client)
- **กลุ่ม 8**: Image Processing from Scratch (PNG Encoder, pHash)
- **กลุ่ม 9**: Data Engineering Primitives (SQLite subset, CSV Aggregator, Parquet Reader)
