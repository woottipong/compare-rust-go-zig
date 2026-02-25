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
└── .windsurf/rules/          # Coding rules
    ├── project-rules.md      # Mandatory rules + checklist
    ├── project-structure.md  # Technical reference
    ├── go-dev.md
    ├── rust-dev.md
    └── zig-dev.md
```

แต่ละ project มีโครงสร้างมาตรฐาน:

```
<project-name>/
├── go/          # Go implementation
├── rust/        # Rust implementation
├── zig/         # Zig implementation
├── test-data/   # ไฟล์สำหรับทดสอบ (gitignored)
├── benchmark/
│   ├── run.sh   # Docker-based benchmark (5 runs: 1 warm-up + 4 measured)
│   └── results/ # ผลลัพธ์ที่บันทึกไว้อัตโนมัติ (gitignored)
└── README.md
```

---

## ผลการเปรียบเทียบ (8/27 Completed)

### 1. Video Frame Extractor
ดึง frame จากวิดีโอที่ตำแหน่ง timestamp → output PPM image

| Metric | Go | Rust | Zig |
|--------|-----|------|-----|
| **Avg Time** | 517ms | 545ms | 583ms |
| **Binary Size** | 1.6MB | **388KB** | 1.4MB |
| **Code Lines** | 182 | 192 | **169** |

**Key insight**: FFmpeg decode เป็น bottleneck → ทุกภาษาเร็วใกล้เคียงกัน

### 2. HLS Stream Segmenter
ตัดวิดีโอ 30s เป็น 3 segments → `.ts` + `playlist.m3u8`

| Metric | Go | Rust | Zig |
|--------|-----|------|-----|
| **Avg Time** | 20,874ms | 16,261ms | **15,572ms** |
| **Binary Size** | 1.6MB | **388KB** | 1.5MB |
| **Code Lines** | 323 | 274 | **266** |

**Key insight**: I/O-bound — Zig/Rust เร็วกว่า Go ใน Docker (FFmpeg decode overhead)

### 3. Subtitle Burn-in Engine
ฝัง SRT subtitle ลงวิดีโอ (decode → burn text → encode H264)

| Metric | Go | Rust | Zig |
|--------|-----|------|-----|
| **Avg Time** | 1,869ms | 1,625ms | **1,350ms** |
| **Binary Size** | 1.6MB | 1.6MB | 2.3MB |
| **Code Lines** | 340 | **230** | 332 |

**Key insight**: Zig เร็วสุด, Rust code กระชับสุด (230L)

### 4. High-Performance Reverse Proxy
Reverse Proxy + Load Balancing (Round-robin) ผ่าน TCP

| Metric | Go | Rust | Zig |
|--------|-----|------|-----|
| **Throughput** | **10,065 req/s** | 3,640 req/s | 2,669 req/s |
| **Avg Latency** | **5.60ms** | 12.66ms | 16.24ms |
| **Binary Size** | 5.2MB | **1.2MB** | 2.4MB |
| **Code Lines** | **158** | 160 | 166 |

**Key insight**: Go ชนะขาดเพราะ `httputil.ReverseProxy` มี connection pooling

### 5. Lightweight API Gateway
HTTP Gateway พร้อม JWT validation, rate limiting, middleware chain

| Metric | Go (Fiber) | Rust (axum) | Zig (Zap) |
|--------|-----------|-------------|----------|
| **Throughput** | 54,919 req/s | **57,056 req/s** | 52,103 req/s |
| **Peak Memory** | 11,344 KB | **2,528 KB** | 27,680 KB |
| **Binary Size** | 9.1MB | 1.6MB | **233KB** |
| **Code Lines** | 209 | 173 | **146** |

**Key insight**: ทุกภาษาอยู่ใน ballpark เดียวกัน (~50–57K req/s) เมื่อใช้ async framework ที่เหมาะสม

### 6. Real-time Audio Chunker
ตัด Audio Stream เป็นท่อนๆ สำหรับ AI (buffer management + latency)

| Metric | Go | Rust | Zig |
|--------|-----|------|-----|
| **Avg Latency** | 0.006ms | 0.061ms | **0.000ms** |
| **Throughput** | 57.81 c/s | 54.56 c/s | 54.87 c/s |
| **Binary Size** | 1.5MB | **452KB** | 2.2MB |
| **Code Lines** | 198 | **180** | 157 |

**Key insight**: Zig latency ต่ำสุดในระดับ nanoseconds สำหรับ buffer operations

### 7. Custom Log Masker
กรองข้อมูล PII ออกจาก Logs — String Processing benchmark

| Metric | Go | **Rust** | Zig |
|--------|-----|----------|-----|
| **Throughput** | 3.91 MB/s | **41.71 MB/s** | 11.68 MB/s |
| **Lines/sec** | 52,280 | **557,891** | 156,234 |
| **Processing Time** | 1.913s | **0.179s** | 0.640s |
| **Code Lines** | 183 | **127** | 473 |

**Key insight**: Rust `regex` crate ใช้ SIMD + DFA engine — เร็วกว่า Go RE2 ถึง **10x**

### 8. Vector DB Ingester
แปลงเอกสารเป็น Vector Embeddings — Memory Management benchmark

| Metric | Go | Rust | **Zig** 🏆 |
|--------|-----|------|-----------|
| **Avg Throughput** | 21,799 c/s | 38,945 c/s | **53,617 c/s** |
| **Avg Time** | 299ms | 229ms | **215ms** |
| **Variance** | 55% | **11%** | 14% |
| **Speedup vs Go** | 1.0x | 1.79x | **2.46x** |

**Key insight**: Zig manual memory management ชนะ 2.46x — Rust มี variance ต่ำสุด (11%)

---

## 🏆 Overall Score (8 projects)

| ภาษา | Wins | จุดเด่น |
|------|------|---------|
| **Zig** | 4 | FFmpeg (vfe/hls/sbe) + Audio latency — เร็วสุดใน memory-intensive tasks |
| **Rust** | 2 | Log masking (10x) + API Gateway — SIMD regex + async I/O |
| **Go** | 2 | Reverse proxy + Frame extractor — connection pooling + stdlib |

---

## Quick Start

### Prerequisites
```bash
# macOS
brew install ffmpeg zig docker

# Ubuntu/Debian
sudo apt-get install libavformat-dev libavcodec-dev libavutil-dev libswscale-dev docker.io
```

### สร้าง Test Data
```bash
# Media projects
cd <project-name>/test-data
ffmpeg -f lavfi -i testsrc=duration=30:size=640x360:rate=25 -pix_fmt yuv420p sample.mp4

# Audio projects
ffmpeg -f lavfi -i sine=frequency=440:duration=10 -ar 16000 -ac 1 -c:a pcm_s16le sample.wav
```

### Run Benchmark
```bash
cd <project-name>
bash benchmark/run.sh
# ผลลัพธ์บันทึกอัตโนมัติใน benchmark/results/
```

### Local Build
```bash
# Go
unset GOROOT && go build -o ../bin/<name>-go .

# Rust
cargo build --release

# Zig
zig build -Doptimize=ReleaseFast
```

---

## Rules & Standards

- **Benchmark**: Docker เสมอ — 5 runs (1 warm-up + 4 measured) สำหรับ non-HTTP
- **Statistics**: `--- Statistics --- / Total processed / Processing time / Average latency / Throughput`
- **README**: 8 sections มาตรฐาน รวม raw benchmark output
- **Docker image**: `<prefix>-go`, `<prefix>-rust`, `<prefix>-zig`

ดู `.windsurf/rules/project-rules.md` สำหรับ checklist และ mandatory rules

---

## Language Summary

| ภาษา | จุดเด่น | จุดที่ต้องระวัง |
|------|---------|----------------|
| **Go** | เขียนง่าย, stdlib ครบ, build เร็ว | CGO memory ซับซ้อน, binary ใหญ่เมื่อใช้ deps |
| **Rust** | Memory safe, performance สม่ำเสมอ, variance ต่ำ | Build time นาน, env vars สำหรับ FFI |
| **Zig** | Binary เล็ก, C interop ตรง, `comptime` ทรงพลัง | Ecosystem เล็ก, API ยัง evolving |

---

## Key Lessons

- **Framework choice**: Zig manual HTTP 8K req/s → Zap 52K req/s (+6x)
- **Regex engine**: Rust SIMD regex เร็วกว่า Go RE2 ถึง 10x
- **Connection pooling**: Go `httputil.ReverseProxy` ชนะขาดด้าน TCP proxy
- **Memory model**: Zig manual memory ให้ throughput สูงสุดในงาน data processing
- **Stability**: Rust variance ต่ำสุด (11%) เหมาะ production workloads
- **Docker overhead**: ~400-500ms container startup รวมใน FFmpeg benchmarks

---

## Projects ที่วางแผนไว้

ดูรายละเอียดทั้งหมดใน [`plan.md`](./plan.md) — 9 กลุ่ม 27 projects (8/27 done)

| กลุ่ม | Projects | สถานะ |
|-------|---------|--------|
| 1 Media (FFmpeg) | vfe, hls, sbe | ✅ Done |
| 2 Networking | proxy, gateway, audio | ✅ Done |
| 3 AI/Data | llm-proxy, vector-db, log-masker | 2/3 Done |
| 4 DevOps | log-aggregator, health-check, watchdog | ⬜ |
| 5 Systems | kv-store, bittorrent, bytecode-vm | ⬜ |
| 6 Integration | sheets-sync, crawler, tor-tracker | ⬜ |
| 7 Low-level Networking | dns, port-scanner, quic | ⬜ |
| 8 Image Processing | png-encoder, jpeg-pipeline, phash | ⬜ |
| 9 Data Engineering | sqlite-engine, csv-aggregator, parquet | ⬜ |
