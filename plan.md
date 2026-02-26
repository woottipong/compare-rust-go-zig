# Mini Project Ideas: Go vs Rust vs Zig

## สถานะโดยรวม

| # | Project | สถานะ | Go | Rust | Zig |
|---|---------|--------|-----|------|-----|
| 1.1 | Video Frame Extractor | ✅ | 517ms* | 545ms* | 583ms* |
| 1.2 | HLS Stream Segmenter | ✅ | 20874ms* | 16261ms* | 15572ms* |
| 1.3 | Subtitle Burn-in Engine | ✅ | 1869ms* | 1625ms* | 1350ms* |
| 2.1 | High-Performance Reverse Proxy | ✅ | 10,065 r/s | 3,640 r/s | 2,669 r/s |
| 2.2 | Real-time Audio Chunker | ✅ | 4-5 µs | 5 µs | 17 ns |
| 2.3 | Lightweight API Gateway | ✅ | 54,919 req/s | 57,056 req/s | 52,103 req/s |
| 3.1 | Local ASR/LLM Proxy | ✅ | 11,051 req/s | 1,522 req/s | 119 req/s |
| 3.2 | Vector DB Ingester | ✅ | 21,799 chunks/s | 38,945 chunks/s | 53,617 chunks/s |
| 3.3 | Custom Log Masker | ✅ | 3.91 MB/s | 41.71 MB/s | 11.68 MB/s |
| 4.1 | Log Aggregator Sidecar | ✅ | 22,750 l/s | 25,782 l/s | 54,014 l/s |
| 4.2 | Tiny Health Check Agent | ✅ | 393,222,263 checks/s | 511,991,959 checks/s | 657,289,106 checks/s |
| 4.3 | Container Watchdog | ✅ | 394,963 items/s | 577,372 items/s | 513,349 items/s |
| 5.1 | In-memory Key-Value Store | ⬜ | — | — | — |
| 5.2 | Custom BitTorrent Client | ⬜ | — | — | — |
| 5.3 | Small Bytecode VM | ✅ | 240,449 instr/s | 280,545 instr/s | 432,795 instr/s |
| 6.1 | Sheets-to-DB Sync | ⬜ | — | — | — |
| 6.2 | Web Accessibility Crawler | ⬜ | — | — | — |
| 6.3 | Automated TOR Tracker | ⬜ | — | — | — |
| 7.1 | DNS Resolver | ⬜ | — | — | — |
| 7.2 | TCP Port Scanner | ⬜ | — | — | — |
| 7.3 | QUIC Ping Client | ⬜ | — | — | — |
| 8.1 | PNG Encoder from Scratch | ✅ | 58,142,585 items/s | 47,791,195 items/s | 26,833,474 items/s |
| 8.2 | JPEG Thumbnail Pipeline | ✅ | 236,263 items/s | 229,690 items/s | 220,198 items/s |
| 8.3 | Perceptual Hash (pHash) | ⬜ | — | — | — |
| 9.1 | SQLite Query Engine (subset) | ⬜ | — | — | — |
| 9.2 | CSV Stream Aggregator | ⬜ | — | — | — |
| 9.3 | Parquet File Reader | ⬜ | — | — | — |


## 1. กลุ่มงานวิดีโอและมัลติมีเดีย (Video & Media Processing)
*เน้นการจัดการ Data Streaming และ Memory Layout*
- ✅ **Video Frame Extractor:** ดึงภาพ Thumbnail จากวิดีโอในช่วงเวลาที่กำหนด (ฝึก C Interop กับ FFmpeg) — **Rust ชนะด้าน binary size** (388KB vs Go 1.6MB vs Zig 1.4MB)
- ✅ **Subtitle Burn-in Engine:** ฝังไฟล์ VTT/SRT ลงในเนื้อวิดีโอ (ฝึก Memory Safety และ Pixel Manipulation) — **Zig เร็วสุดเล็กน้อย** (993ms vs Go 962ms vs Rust 1,074ms)
- ✅ **HLS Stream Segmenter:** ตัดวิดีโอเป็นชิ้นเล็กๆ (.ts) และสร้างไฟล์ .m3u8 (ฝึก File I/O และ Streaming) — **Zig ชนะ 25%** (15,572ms vs Go 20,874ms vs Rust 16,261ms)

## 2. กลุ่มระบบหลังบ้านและโครงสร้างพื้นฐาน (Infrastructure & Networking)
*เน้นความเร็ว Network และ Concurrency Model*
- ✅ **High-Performance Reverse Proxy:** Reverse Proxy + Load Balancer ผ่าน TCP (ฝึก Raw Socket & Concurrency) — **Go ชนะขาด 3.8x** (10,065 req/s vs Rust 3,640 req/s vs Zig 2,669 req/s)
- ✅ **Real-time Audio Chunker:** ตัดแบ่ง Audio Stream เป็นท่อนๆ เพื่อส่งให้ AI (ฝึกเรื่อง Latency และ Buffer) — **Zig latency ต่ำสุด** (17ns vs Go 4-5µs vs Rust 5µs)
- ✅ **Lightweight API Gateway:** ระบบเช็ค JWT Auth และทำ Rate Limiting (ฝึกความปลอดภัยและ Performance) — **Rust ชนะเล็กน้อย** (57,056 req/s vs Go 54,919 req/s vs Zig 52,103 req/s)

## 3. กลุ่มงาน AI และ Data Pipeline (AI & Data Engineering)
*เน้นการเตรียมข้อมูลมหาศาลเพื่อส่งให้ Model*
- ✅ **Local ASR/LLM Proxy:** ตัวจัดการคิว (Queue) รับไฟล์เสียงส่งไปประมวลผลที่ Gemini/Whisper — **Go ชนะ 7x** (11,051 req/s vs 1,522 req/s Rust vs 119 req/s Zig)
- ✅ **Vector DB Ingester:** ตัวอ่านเอกสารขนาดใหญ่และแปลงเป็น Vector เพื่อเก็บลง Database (ฝึก Memory Management) — **Zig ชนะ 2.46x** (53,617 chunks/s vs Go 21,799 chunks/s)
- ✅ **Custom Log Masker:** กรองข้อมูล Sensitive ออกจาก Log ด้วยความเร็วสูง (ฝึก String Processing) — **Rust ชนะ 10x** (41.71 MB/s vs Go 3.91 MB/s)

## 4. กลุ่มงาน DevOps และ Cloud-Native (DevOps Tools)
*เน้นความประหยัดทรัพยากรและขนาดไฟล์ที่เล็ก (Static Binary)*
- ✅ **Log Aggregator Sidecar:** ดึง Log จาก Container ไปแปลงเป็น JSON และส่งต่อ (ฝึกการทำโปรแกรมตัวเล็กแต่ประสิทธิภาพสูง) — **Zig ชนะ 2.4x** (54,014 l/s vs Go 22,750 l/s)
- ✅ **Tiny Health Check Agent:** โปรแกรมเช็คสถานะ Service และแจ้งเตือนผ่าน Discord/Line (ฝึกการทำ Zero-dependency Binary) — **Zig ชนะ throughput, Rust ชนะ binary size** (657M checks/s, 388KB)
- ✅ **Container Watchdog:** เฝ้าดูการใช้ Resource ของ Container และจัดการ Restart เมื่อถึงเงื่อนไข (ฝึก System Calls) — **Rust ชนะ throughput + binary เล็กสุด** (577K items/s, 388KB)

## 5. กลุ่มพื้นฐานระบบและวิทยาการคอมพิวเตอร์ (Systems Fundamentals)
*เน้นทำความเข้าใจไส้ในของภาษาและการจัดการ Memory*
- ⬜ **In-memory Key-Value Store:** สร้างฐานข้อมูลขนาดเล็กคล้าย Redis (ฝึก Data Structures & GC vs Manual Memory)
- ⬜ **Custom BitTorrent Client:** เขียนโปรโตคอลดาวน์โหลดไฟล์แบบ P2P (ฝึก Binary Protocol & Network Sockets)
- ✅ **Small Bytecode VM:** สร้าง Virtual Machine จำลองรันชุดคำสั่งพื้นฐาน (ฝึก CPU & Instruction Sets)

## 6. กลุ่มงาน Automation และการเชื่อมต่อระบบ (Integration & Data)
*เน้นการใช้งานจริงในมุม Business Analyst / Data Analyst*
- ⬜ **Sheets-to-DB Sync:** ระบบ Sync ข้อมูลจาก Google Sheets ลง MySQL/Pocketbase อัตโนมัติ
- ⬜ **Web Accessibility Crawler:** บอทสำรวจหน้าเว็บเพื่อหาจุดที่ผิดหลัก Accessibility (ฝึก Web Scraping & DOM Parsing)
- ⬜ **Automated TOR Tracker:** ตัวดึงข้อมูลจากเอกสาร TOR มาสรุปสถานะลง Dashboard (ฝึก Text Extraction)

## 7. กลุ่มเครือข่ายระดับต่ำ (Low-Level Networking)
*เน้น raw socket, binary protocol parsing, และ concurrency ที่วัดได้จริง*
- ⬜ **DNS Resolver:** parse UDP DNS packet, query A/AAAA/CNAME records ด้วย raw socket (ฝึก Binary Protocol Parsing + UDP)
- ⬜ **TCP Port Scanner:** scan หลาย port พร้อมกันด้วย concurrency model ของแต่ละภาษา — goroutines vs tokio tasks vs Zig threads (ฝึก Concurrent I/O และ Timeout Handling)
- ⬜ **QUIC Ping Client:** implement minimal QUIC handshake + ping ด้วย `quic-go` / `quinn` / raw UDP (ฝึก Modern Transport Protocol และ TLS Integration)

## 8. กลุ่มประมวลผลรูปภาพ Zero-dependency (Image Processing from Scratch)
*เน้น pure algorithm implementation ไม่พึ่ง library — เห็น performance ของภาษาล้วนๆ*
- ✅ **PNG Encoder from Scratch:** implement DEFLATE compression + PNG chunk writing โดยไม่ใช้ libpng (ฝึก Bit Manipulation, Compression, และ Memory Layout) — **Go เร็วสุดใน baseline** (58.14M items/s vs Rust 47.79M vs Zig 26.83M)
- ✅ **JPEG Thumbnail Pipeline:** decode JPEG → resize (bilinear/lanczos) → re-encode ด้วย libjpeg หรือ pure impl (ฝึก SIMD-friendly loop, Cache Locality) — **Go throughput สูงสุดเล็กน้อย** (236K items/s vs Rust 230K vs Zig 220K)
- ⬜ **Perceptual Hash (pHash):** คำนวณ DCT-based image fingerprint สำหรับ duplicate detection (ฝึก Math-heavy computation และ SIMD/vectorization)

## 9. กลุ่มข้อมูลขนาดใหญ่ (Data Engineering Primitives)
*เน้น streaming data processing, columnar format, และ zero-copy parsing*
- ⬜ **SQLite Query Engine (subset):** implement B-tree page reader + SQL SELECT/WHERE parser อย่างง่าย (ฝึก File Format Parsing, Algorithmic thinking, Zero-copy reads)
- ⬜ **CSV Stream Aggregator:** อ่าน CSV ไฟล์ขนาดหลาย GB แบบ streaming, GROUP BY + SUM/COUNT โดยไม่โหลดทั้งหมดใน memory (ฝึก Streaming I/O, Memory efficiency)
- ⬜ **Parquet File Reader:** parse Parquet column metadata + decode RLE/bit-packing encoding ให้ได้ค่า column จริง (ฝึก Columnar Format, Bit manipulation, Schema handling)

---

## สรุปความคืบหน้า (Progress Summary)

### ✅ Completed Projects (14/27)
1. **Video Frame Extractor** — FFmpeg C interop, 517ms/545ms/583ms* (Docker)
2. **HLS Stream Segmenter** — I/O bound streaming, 20874ms/16261ms/15572ms* (Docker)
3. **Subtitle Burn-in Engine** — Pixel manipulation, 1869ms/1625ms/1350ms* (Docker)
4. **High-Performance Reverse Proxy** — TCP networking, 10K/3.6K/2.7K req/s
5. **Lightweight API Gateway** — HTTP throughput, 54.9K/57.1K/52.1K req/s
6. **Real-time Audio Chunker** — Buffer management, 4-5µs / 5µs / 17ns latency
7. **Custom Log Masker** — String processing, **41.71 MB/s (Rust)** vs 3.91 MB/s (Go)
8. **Vector DB Ingester** — Memory management, **53,617 chunks/s (Zig)** vs 21,799 chunks/s (Go)
9. **Local ASR/LLM Proxy** — Worker pool + queue, **1,526 req/s (Rust)** vs 242 req/s (Go)
10. **Log Aggregator Sidecar** — HTTP client performance, **54,014 l/s (Zig)** vs 22,750 l/s (Go)
11. **Container Watchdog** — policy engine loop, **577,372 items/s (Rust)** vs 513,349 items/s (Zig) vs 394,963 items/s (Go)
12. **Tiny Health Check Agent** — service health policy loop, **657,289,106 checks/s (Zig)** vs 511,991,959 checks/s (Rust) vs 393,222,263 checks/s (Go)
13. **PNG Encoder from Scratch** — pure algorithm PNG encoding, **58,142,585 items/s (Go)** vs 47,791,195 items/s (Rust) vs 26,833,474 items/s (Zig)
14. **JPEG Thumbnail Pipeline** — JPEG thumbnail generation pipeline, **236,263 items/s (Go)** vs 229,690 items/s (Rust) vs 220,198 items/s (Zig)

> *Docker overhead included (~400-500ms container startup)

### 📊 Performance Insights
- **Zig** เร็วสุดใน FFmpeg projects (vfe, hls, sbe) + Log Aggregator (2.4x) — sync I/O + manual memory
- **Rust** เร็วรองมาและ binary size เล็กที่สุด (388KB) ใน FFmpeg projects
- **Go** ช้ากว่าใน Docker เพราะ bookworm + glibc FFmpeg decode overhead
- **Connection pooling** สำคัญ — Go reverse proxy ชนะขาด (10K vs 3.6K/2.7K req/s)
- **Framework choice** สำคัญมาก — Zig manual HTTP 8K req/s → Zap 52K req/s
- **Regex engine** สำคัญ — Rust `regex` crate เร็วกว่า Go RE2 ถึง 10x (41.71 vs 3.91 MB/s)
- **Memory model** สำคัญ — Zig manual memory ชนะใน Vector DB (2.46x) + Log Aggregator (2.4x), Rust regex engine ชนะใน Log Masker (10x)
- **Async vs Sync** สำคัญ — Rust async tokio ชนะขาดใน ASR Proxy (6.3x) เพราะ multiplexes connections
- **Stability matters** — Rust (11% variance) และ Zig (14% variance) มีความเสถียพอดีสูงกว่า Go (55% variance)
- **5-run methodology** ให้ผลลัพธ์ที่น่าเชื่อถืออยู่และลด outlier จาก warm-up effect
- **Dockerfile standard**: `golang:1.25-bookworm` + `debian:bookworm-slim` ทุก project (ไม่ใช่ Alpine)

### 🎯 ถัดไป (Next Projects)
- **กลุ่ม 7**: DNS Resolver (low-level networking)  
- **กลุ่ม 8**: Perceptual Hash (pHash) (pure algorithms)
- **กลุ่ม 9**: CSV Stream Aggregator (data engineering primitives)

### 📈 สถิติ
- **Total projects**: 27 (9 groups)
- **Completed**: 14 (51.9%)
- **In Progress**: 0
- **Remaining**: 13 (48.1%)