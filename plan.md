# Mini Project Ideas: Go vs Rust vs Zig

## สถานะโดยรวม

| # | Project | สถานะ | Go | Rust | Zig |
|---|---------|--------|-----|------|-----|
| 1.1 | Video Frame Extractor | ✅ Done | 50ms | 76ms | 51ms |
| 1.2 | HLS Stream Segmenter | ✅ Done | 1452ms | 1395ms | 1380ms |
| 1.3 | Subtitle Burn-in Engine | ⬜ | — | — | — |
| 2.1 | High-Performance Reverse Proxy | ⬜ | — | — | — |
| 2.2 | Real-time Audio Chunker | ⬜ | — | — | — |
| 2.3 | Lightweight API Gateway | ⬜ | — | — | — |
| 3.1 | Local ASR/LLM Proxy | ⬜ | — | — | — |
| 3.2 | Vector DB Ingester | ⬜ | — | — | — |
| 3.3 | Custom Log Masker | ⬜ | — | — | — |
| 4.1 | Log Aggregator Sidecar | ⬜ | — | — | — |
| 4.2 | Tiny Health Check Agent | ⬜ | — | — | — |
| 4.3 | Container Watchdog | ⬜ | — | — | — |
| 5.1 | In-memory Key-Value Store | ⬜ | — | — | — |
| 5.2 | Custom BitTorrent Client | ⬜ | — | — | — |
| 5.3 | Small Bytecode VM | ⬜ | — | — | — |
| 6.1 | Sheets-to-DB Sync | ⬜ | — | — | — |
| 6.2 | Web Accessibility Crawler | ⬜ | — | — | — |
| 6.3 | Automated TOR Tracker | ⬜ | — | — | — |
| 7.1 | DNS Resolver | ⬜ | — | — | — |
| 7.2 | TCP Port Scanner | ⬜ | — | — | — |
| 7.3 | QUIC Ping Client | ⬜ | — | — | — |
| 8.1 | PNG Encoder from Scratch | ⬜ | — | — | — |
| 8.2 | JPEG Thumbnail Pipeline | ⬜ | — | — | — |
| 8.3 | Perceptual Hash (pHash) | ⬜ | — | — | — |
| 9.1 | SQLite Query Engine (subset) | ⬜ | — | — | — |
| 9.2 | CSV Stream Aggregator | ⬜ | — | — | — |
| 9.3 | Parquet File Reader | ⬜ | — | — | — |


## 1. กลุ่มงานวิดีโอและมัลติมีเดีย (Video & Media Processing)
*เน้นการจัดการ Data Streaming และ Memory Layout*
- ✅ **Video Frame Extractor:** ดึงภาพ Thumbnail จากวิดีโอในช่วงเวลาที่กำหนด (ฝึก C Interop กับ FFmpeg)
- ⬜ **Subtitle Burn-in Engine:** ฝังไฟล์ VTT/SRT ลงในเนื้อวิดีโอ (ฝึก Memory Safety และ Pixel Manipulation)
- ✅ **HLS Stream Segmenter:** ตัดวิดีโอเป็นชิ้นเล็กๆ (.ts) และสร้างไฟล์ .m3u8 (ฝึก File I/O และ Streaming)

## 2. กลุ่มระบบหลังบ้านและโครงสร้างพื้นฐาน (Infrastructure & Networking)
*เน้นความเร็ว Network และ Concurrency Model*
- ⬜ **High-Performance Reverse Proxy:** ตัวกลางรับ Request และทำ Load Balancer (ฝึก Concurrency & Networking)
- ⬜ **Real-time Audio Chunker:** ตัดแบ่ง Audio Stream เป็นท่อนๆ เพื่อส่งให้ AI (ฝึกเรื่อง Latency และ Buffer)
- ⬜ **Lightweight API Gateway:** ระบบเช็ค JWT Auth และทำ Rate Limiting (ฝึกความปลอดภัยและ Performance)

## 3. กลุ่มงาน AI และ Data Pipeline (AI & Data Engineering)
*เน้นการเตรียมข้อมูลมหาศาลเพื่อส่งให้ Model*
- ⬜ **Local ASR/LLM Proxy:** ตัวจัดการคิว (Queue) รับไฟล์เสียงส่งไปประมวลผลที่ Gemini/Whisper
- ⬜ **Vector DB Ingester:** ตัวอ่านเอกสารขนาดใหญ่และแปลงเป็น Vector เพื่อเก็บลง Database (ฝึก Memory Management)
- ⬜ **Custom Log Masker:** กรองข้อมูล Sensitive ออกจาก Log ด้วยความเร็วสูงก่อนบันทึก (ฝึก String Processing)

## 4. กลุ่มงาน DevOps และ Cloud-Native (DevOps Tools)
*เน้นความประหยัดทรัพยากรและขนาดไฟล์ที่เล็ก (Static Binary)*
- ⬜ **Log Aggregator Sidecar:** ดึง Log จาก Container ไปแปลงเป็น JSON และส่งต่อ (ฝึกการทำโปรแกรมตัวเล็กแต่ประสิทธิภาพสูง)
- ⬜ **Tiny Health Check Agent:** โปรแกรมเช็คสถานะ Service และแจ้งเตือนผ่าน Discord/Line (ฝึกการทำ Zero-dependency Binary)
- ⬜ **Container Watchdog:** เฝ้าดูการใช้ Resource ของ Container และจัดการ Restart เมื่อถึงเงื่อนไข (ฝึก System Calls)

## 5. กลุ่มพื้นฐานระบบและวิทยาการคอมพิวเตอร์ (Systems Fundamentals)
*เน้นทำความเข้าใจไส้ในของภาษาและการจัดการ Memory*
- ⬜ **In-memory Key-Value Store:** สร้างฐานข้อมูลขนาดเล็กคล้าย Redis (ฝึก Data Structures & GC vs Manual Memory)
- ⬜ **Custom BitTorrent Client:** เขียนโปรโตคอลดาวน์โหลดไฟล์แบบ P2P (ฝึก Binary Protocol & Network Sockets)
- ⬜ **Small Bytecode VM:** สร้าง Virtual Machine จำลองรันชุดคำสั่งพื้นฐาน (ฝึก CPU & Instruction Sets)

## 6. กลุ่มงาน Automation และการเชื่อมต่อระบบ (Integration & Data)
*เน้นการใช้งานจริงในมุม Business Analyst / Data Analyst*
- ⬜ **Sheets-to-DB Sync:** ระบบ Sync ข้อมูลจาก Google Sheets ลง MySQL/Pocketbase อัตโนมัติ
- ⬜ **Web Accessibility Crawler:** บอทสำรวจหน้าเว็บเพื่อหาจุดที่ผิดหลัก Accessibility (ฝึก Web Scraping & DOM Parsing)
- ⬜ **Automated TOR Tracker:** ตัวดึงข้อมูลจากเอกสาร TOR มาสรุปสถานะลง Dashboard (ฝึก Text Extraction)

## 7. กลุ่มเครือข่ายระดับต่ำ (Low-Level Networking) ⭐ ใหม่
*เน้น raw socket, binary protocol parsing, และ concurrency ที่วัดได้จริง*
- ⬜ **DNS Resolver:** parse UDP DNS packet, query A/AAAA/CNAME records ด้วย raw socket (ฝึก Binary Protocol Parsing + UDP)
- ⬜ **TCP Port Scanner:** scan หลาย port พร้อมกันด้วย concurrency model ของแต่ละภาษา — goroutines vs tokio tasks vs Zig threads (ฝึก Concurrent I/O และ Timeout Handling)
- ⬜ **QUIC Ping Client:** implement minimal QUIC handshake + ping ด้วย `quic-go` / `quinn` / raw UDP (ฝึก Modern Transport Protocol และ TLS Integration)

## 8. กลุ่มประมวลผลรูปภาพ Zero-dependency (Image Processing from Scratch) ⭐ ใหม่
*เน้น pure algorithm implementation ไม่พึ่ง library — เห็น performance ของภาษาล้วนๆ*
- ⬜ **PNG Encoder from Scratch:** implement DEFLATE compression + PNG chunk writing โดยไม่ใช้ libpng (ฝึก Bit Manipulation, Compression, และ Memory Layout)
- ⬜ **JPEG Thumbnail Pipeline:** decode JPEG → resize (bilinear/lanczos) → re-encode ด้วย libjpeg หรือ pure impl (ฝึก SIMD-friendly loop, Cache Locality)
- ⬜ **Perceptual Hash (pHash):** คำนวณ DCT-based image fingerprint สำหรับ duplicate detection (ฝึก Math-heavy computation และ SIMD/vectorization)

## 9. กลุ่มข้อมูลขนาดใหญ่ (Data Engineering Primitives) ⭐ ใหม่
*เน้น streaming data processing, columnar format, และ zero-copy parsing*
- ⬜ **SQLite Query Engine (subset):** implement B-tree page reader + SQL SELECT/WHERE parser อย่างง่าย (ฝึก File Format Parsing, Algorithmic thinking, Zero-copy reads)
- ⬜ **CSV Stream Aggregator:** อ่าน CSV ไฟล์ขนาดหลาย GB แบบ streaming, GROUP BY + SUM/COUNT โดยไม่โหลดทั้งหมดใน memory (ฝึก Streaming I/O, Memory efficiency)
- ⬜ **Parquet File Reader:** parse Parquet column metadata + decode RLE/bit-packing encoding ให้ได้ค่า column จริง (ฝึก Columnar Format, Bit manipulation, Schema handling)