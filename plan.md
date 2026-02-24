# Mini Project Ideas: Go vs Rust vs Zig

## สถานะโดยรวม

| # | Project | สถานะ | Go | Rust | Zig |
|---|---------|--------|-----|------|-----|
| 1.1 | Video Frame Extractor | ✅ Done | 50ms | 76ms | 51ms |
| 1.2 | HLS Stream Segmenter | ✅ Done | 1452ms | 1395ms | 1380ms |
| 1.3 | Subtitle Burn-in Engine | ⬜ Next (ถ้าอยู่ใน Video group) | — | — | — |
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

---

## 🏆 แนะนำ Next Project

### ตัวเลือก A — ต่อเนื่องใน Video group
**Subtitle Burn-in Engine** (1.3) — ฝัง SRT/VTT ลงในวิดีโอ
- ✦ ใช้ `libass` + `libavfilter` → C interop ที่ซับซ้อนกว่าเดิม
- ✦ ต้อง re-encode → เห็น encode performance ครั้งแรก
- ✦ Pixel blending → ทดสอบ Memory Safety จริงๆ

### ตัวเลือก B — ข้ามไป Networking
**Lightweight API Gateway** (2.3) — JWT Auth + Rate Limiting
- ✦ เห็น Concurrency model ชัดที่สุด (goroutines vs tokio vs manual)
- ✦ ไม่ต้องพึ่ง FFmpeg → ทดสอบ core language ล้วน
- ✦ Go จะชนะชัดในด้าน networking throughput

### ตัวเลือก C — Systems Fundamentals
**In-memory Key-Value Store** (5.1) — Redis-like store
- ✦ เห็น GC vs Manual Memory vs Zig comptime ชัดเจนที่สุด
- ✦ ง่ายสุดในแง่ dependencies (zero external libs)
- ✦ เหมาะสำหรับ pure language benchmark

---

## Lessons Learned จากโปรเจกต์ที่ทำแล้ว

### video-frame-extractor
- FFmpeg 8.0: ใช้ `ffmpeg-sys-next = "8.0"` เท่านั้น
- Zig 0.15: `createModule()` + `root_module` syntax
- Go CGO: `*(**C.AVStream)` pattern สำหรับ access C array
- ทุกภาษา ~50ms → FFmpeg decode เป็น bottleneck หลัก

### hls-stream-segmenter
- **Critical bug**: ต้องเปิด segment file ค้างไว้ระหว่าง frames (persistent file handle)
- Zig: ใช้ `cwd().createFile()` ไม่ใช่ `createFileAbsolute()` สำหรับ relative paths
- Rust: `Option<File>` pattern สำหรับ conditional resource ownership
- ทุกภาษา ~1.4s → I/O (write raw YUV420P per frame) เป็น bottleneck

---

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