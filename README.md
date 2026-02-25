# Compare Rust / Go / Zig

เปรียบเทียบการเขียนโปรแกรมด้วย **Go**, **Rust**, และ **Zig** ผ่าน mini projects จริงๆ
เน้นวัดผล performance, binary size, memory usage, และ code complexity ในแต่ละโดเมน

---

## โครงสร้าง Repository

```
compare-rust-go-zig/
├── video-frame-extractor/    ✅ ดึง frame thumbnail จากวิดีโอ (FFmpeg C interop)
├── hls-stream-segmenter/     ✅ ตัดวิดีโอเป็น .ts + .m3u8 (HLS streaming)
├── subtitle-burn-in-engine/  ✅ ฝัง SRT subtitle ลงวิดีโอ + re-encode H264
├── high-perf-reverse-proxy/  ✅ Reverse Proxy + Load Balancer (TCP networking)
├── lightweight-api-gateway/  ✅ API Gateway: JWT, rate limiting, reverse proxy
├── realtime-audio-chunker/   ✅ Real-time Audio Chunker (buffer management)
├── custom-log-masker/        ✅ Log PII masking (string processing)
├── vector-db-ingester/       ✅ Vector embeddings generation (memory management)
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
| **Avg Time** (Docker) | 517ms | **545ms** | 583ms |
| **Binary Size** | 1.6MB | **388KB** | 1.4MB |
| **Code Lines** | 182 | 192 | **169** |

**Key insight**: FFmpeg decode เป็น bottleneck → ทุกภาษาเร็วใกล้เคียงกัน (Docker overhead ~400ms)

### 2. HLS Stream Segmenter
ตัดวิดีโอ 30s เป็น 3 segments (10s each) → `.ts` + `playlist.m3u8`

| Metric | Go | Rust | Zig |
|--------|-----|------|-----|
| **Avg Time** (Docker) | 20874ms | 16261ms | **15572ms** |
| **Binary Size** | 1.6MB | **388KB** | 1.5MB |
| **Code Lines** | 323 | 274 | **266** |

**Key insight**: I/O-bound task — Zig/Rust เร็วกว่า Go ใน Docker (bookworm FFmpeg decode overhead)

### 3. Subtitle Burn-in Engine
ฝัง SRT subtitle ลงในวิดีโอโดยตรง (decode → burn text → encode H264)

| Metric | Go | Rust | Zig |
|--------|-----|------|-----|
| **Avg Time** (Docker) | 1869ms | 1625ms | **1350ms** |
| **Binary Size** | 1.6MB | 1.6MB | 2.3MB |
| **Code Lines** | 340 | **230** | 332 |

**Key insight**: Zig เร็วสุด, Rust code กระชับสุด (230L) — FFmpeg decode+encode เป็น bottleneck

### 4. High-Performance Reverse Proxy
Reverse Proxy พร้อม Load Balancing (Round-robin) — เชื่อมต่อ backend ผ่าน TCP

| Metric | Go | Rust | Zig |
|--------|-----|------|-----|
| **Throughput** | **10,065 req/s** | 3,640 req/s | 2,669 req/s |
| **Avg Latency** | **5.60ms** | 12.66ms | 16.24ms |
| **Binary Size** | 5.2MB | **1.2MB** | 2.4MB |
| **Code Lines** | **158** | 160 | 166 |

**Key insight**: Go ชนะขาดเพราะ `httputil.ReverseProxy` มี connection pooling — reuse TCP connections ลด handshake overhead ส่วน Rust/Zig ใช้ raw TCP (new connection ต่อ request)

### 5. Lightweight API Gateway
HTTP API Gateway พร้อม JWT validation, rate limiting, middleware chain

| Metric | Go (Fiber) | Rust (axum) | Zig (Zap) |
|--------|-----------|-------------|----------|
| **Throughput** | 54,919 req/s | **57,056 req/s** | 52,103 req/s |
| **Peak Memory** | 11,344 KB | **2,528 KB** | 27,680 KB |
| **Binary Size** | 9.1MB | 1.6MB | **233KB** |
| **Code Lines** | 209 | 173 | **146** |

**Key insight**: เมื่อใช้ async framework ที่เหมาะสม ทุกภาษาอยู่ใน ballpark เดียวกัน (~50–57K req/s)

### 6. Real-time Audio Chunker
ตัด Audio Stream เป็นท่อนๆ สำหรับส่งให้ AI (ฝึก Buffer Management และ Latency)

| Metric | Go | Rust | Zig |
|--------|-----|------|-----|
| **Avg Latency** | 0.006 ms | 0.061 ms | **0.000 ms** |
| **Throughput** | 57.81 chunks/s | 54.56 chunks/s | 54.87 chunks/s |
| **Binary Size** | 1.5MB | **452KB** | 2.2MB |
| **Code Lines** | 198 | **180** | 157 |

**Key insight**: Zig เร็วที่สุดในระดับ nanoseconds สำหรับ buffer operations

### 7. Custom Log Masker
กรองข้อมูล Sensitive (PII) จาก Logs ด้วยความเร็วสูง — String Processing benchmark

| Metric | Go | **Rust** | Zig |
|--------|-----|----------|-----|
| **Throughput** | 3.91 MB/s | **41.71 MB/s** (10x) | 11.68 MB/s |
| **Lines/sec** | 52,280 | **557,891** (10x) | 156,234 |
| **Processing Time** | 1.913s | **0.179s** | 0.640s |
| **Binary Size** | **1.8MB** | 1.9MB | 2.2MB |
| **Code Lines** | 183 | **127** | 473 |

**Key insight**: Rust `regex` crate ใช้ SIMD optimizations + DFA engine — เร็วกว่า Go RE2 ถึง 10 เท่า

### 8. Vector DB Ingester
แปลงเอกสารเป็น Vector Embeddings สำหรับ Vector Database — Memory Management benchmark

| Metric | Go | **Rust** | **Zig** 🏆 |
|--------|-----|----------|-----------|
| **Avg Throughput** | 21,799 chunks/s | 38,945 chunks/s | **53,617 chunks/s** |
| **Avg Processing Time** | 299ms | 229ms | **215ms** |
| **Variance** | 55% | **11%** | **14%** |
| **Speedup vs Go** | 1.0x | **1.79x** | **2.46x** |

**Key insight**: Zig manual memory management ชนะด้วยเสถียพอดีและเสถียพอดี (14% variance) — Rust มีความเสถียพอดีสูงสุด (11% variance)

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

### Run Benchmark (Local)
```bash
cd <project-name>
bash benchmark/run.sh test-data/sample.mp4 [param]

# API Gateway
cd lightweight-api-gateway
bash benchmark/run.sh
```

### Run Benchmark via Docker
```bash
# ต้องมี Docker ติดตั้งแล้ว — ไม่ต้อง install toolchain ในเครื่อง
cd <project-name>
bash benchmark/run.sh --docker

# หรือ build images เองก่อนแล้วรัน
docker build -t <prefix>-go   go/
docker build -t <prefix>-rust rust/
docker build -t <prefix>-zig  zig/
bash benchmark/run.sh --docker
```

| Project | Go image | Rust image | Zig image |
|---------|----------|------------|-----------|
| video-frame-extractor | `vfe-go` | `vfe-rust` | `vfe-zig` |
| hls-stream-segmenter | `hls-go` | `hls-rust` | `hls-zig` |
| subtitle-burn-in-engine | `sbe-go` | `sbe-rust` | `sbe-zig` |
| lightweight-api-gateway | `gw-go` | `gw-rust` | `gw-zig` |

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
| **Go** | เขียนง่าย, stdlib ครบ, build เร็ว, Fiber/net/http ยืดหยุ่น | CGO memory leak ง่าย, binary ใหญ่เมื่อใช้ deps |
| **Rust** | Memory safe, ไม่มี GC, performance สม่ำเสมอ, binary กลาง | Build time นาน, env vars สำหรับ FFI |
| **Zig** | Binary เล็กที่สุด, C interop ตรง, `comptime` ทรงพลัง | Ecosystem เล็ก — ต้องพึ่ง C libraries (Zap→facil.io) |

---

## Lessons Learned

### video-frame-extractor
- FFmpeg 8.0: ใช้ `ffmpeg-sys-next = "8.0"` สำหรับ Rust (ไม่ใช่ `ffmpeg-next`)
- Zig 0.15+: ใช้ `createModule()` + `root_module` syntax ใน `build.zig`
- Go CGO: `*(**C.AVStream)` pattern สำหรับ access C pointer array
- Dockerfile: `golang:1.25-bookworm` + `debian:bookworm-slim` (ทุก FFmpeg project)

### hls-stream-segmenter
- **Critical**: ต้องเปิด segment file ค้างไว้ระหว่าง frames ไมเปิด/ปิดทุก frame
- Go CGO + bookworm arm64: `*C.SwsContext` field ใน struct ไม่ทำงาน — ใช้ C helper wrapper function แทน
- Zig: ใช้ `cwd().createFile()` ไม่ใช่ `createFileAbsolute()` สำหรับ relative paths
- Rust: `Option<File>` pattern สำหรับ conditional resource ownership

### subtitle-burn-in-engine
- Simple white-bar overlay ไม่ใช้ libass — FFmpeg pixel manipulation โดยตรง
- Go `golang:1.25-bookworm` ทำงานได้เพราะไม่มี `*C.SwsContext` field ใน struct

### lightweight-api-gateway
- Rust `SocketAddr`: `:8080` parse ไม่ได้ → แปลงเป็น `127.0.0.1:8080` ก่อน
- Go Fiber: binary ใหญ่ (9.1MB) เพราะ fasthttp + dependencies
- Zig manual HTTP: single-threaded → throughput ต่ำ (8K req/s) → ใช้ **Zap** แทน (52K req/s)
- Zap ต้อง copy `libfacil.io.dylib` ไปด้วย และ set `DYLD_LIBRARY_PATH` บน macOS
- ใช้ `wrk` แทน `ab` สำหรับ HTTP benchmark บน macOS

---

## Projects ที่วางแผนไว้

ดูรายละเอียดทั้งหมดใน [`plan.md`](./plan.md) — มี 9 กลุ่ม 27 projects

กลุ่มใหม่ที่น่าสนใจ:
- **กลุ่ม 7**: Low-Level Networking (DNS Resolver, TCP Port Scanner, QUIC Client)
- **กลุ่ม 8**: Image Processing from Scratch (PNG Encoder, pHash)
- **กลุ่ม 9**: Data Engineering Primitives (SQLite subset, CSV Aggregator, Parquet Reader)
