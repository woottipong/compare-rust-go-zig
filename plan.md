# Mini Project Ideas: Go vs Rust vs Zig

## 1. กลุ่มงานวิดีโอและมัลติมีเดีย (Video & Media Processing)
*เน้นการจัดการ Data Streaming และ Memory Layout*
- **Video Frame Extractor:** ดึงภาพ Thumbnail จากวิดีโอในช่วงเวลาที่กำหนด (ฝึก C Interop กับ FFmpeg)
- **Subtitle Burn-in Engine:** ฝังไฟล์ VTT/SRT ลงในเนื้อวิดีโอ (ฝึก Memory Safety และ Pixel Manipulation)
- **HLS Stream Segmenter:** ตัดวิดีโอเป็นชิ้นเล็กๆ (.ts) และสร้างไฟล์ .m3u8 (ฝึก File I/O และ Streaming)

## 2. กลุ่มระบบหลังบ้านและโครงสร้างพื้นฐาน (Infrastructure & Networking)
*เน้นความเร็ว Network และ Concurrency Model*
- **High-Performance Reverse Proxy:** ตัวกลางรับ Request และทำ Load Balancer (ฝึก Concurrency & Networking)
- **Real-time Audio Chunker:** ตัดแบ่ง Audio Stream เป็นท่อนๆ เพื่อส่งให้ AI (ฝึกเรื่อง Latency และ Buffer)
- **Lightweight API Gateway:** ระบบเช็ค JWT Auth และทำ Rate Limiting (ฝึกความปลอดภัยและ Performance)

## 3. กลุ่มงาน AI และ Data Pipeline (AI & Data Engineering)
*เน้นการเตรียมข้อมูลมหาศาลเพื่อส่งให้ Model*
- **Local ASR/LLM Proxy:** ตัวจัดการคิว (Queue) รับไฟล์เสียงส่งไปประมวลผลที่ Gemini/Whisper
- **Vector DB Ingester:** ตัวอ่านเอกสารขนาดใหญ่และแปลงเป็น Vector เพื่อเก็บลง Database (ฝึก Memory Management)
- **Custom Log Masker:** กรองข้อมูล Sensitive ออกจาก Log ด้วยความเร็วสูงก่อนบันทึก (ฝึก String Processing)

## 4. กลุ่มงาน DevOps และ Cloud-Native (DevOps Tools)
*เน้นความประหยัดทรัพยากรและขนาดไฟล์ที่เล็ก (Static Binary)*
- **Log Aggregator Sidecar:** ดึง Log จาก Container ไปแปลงเป็น JSON และส่งต่อ (ฝึกการทำโปรแกรมตัวเล็กแต่ประสิทธิภาพสูง)
- **Tiny Health Check Agent:** โปรแกรมเช็คสถานะ Service และแจ้งเตือนผ่าน Discord/Line (ฝึกการทำ Zero-dependency Binary)
- **Container Watchdog:** เฝ้าดูการใช้ Resource ของ Container และจัดการ Restart เมื่อถึงเงื่อนไข (ฝึก System Calls)

## 5. กลุ่มพื้นฐานระบบและวิทยาการคอมพิวเตอร์ (Systems Fundamentals)
*เน้นทำความเข้าใจไส้ในของภาษาและการจัดการ Memory*
- **In-memory Key-Value Store:** สร้างฐานข้อมูลขนาดเล็กคล้าย Redis (ฝึก Data Structures & GC vs Manual Memory)
- **Custom BitTorrent Client:** เขียนโปรโตคอลดาวน์โหลดไฟล์แบบ P2P (ฝึก Binary Protocol & Network Sockets)
- **Small Bytecode VM:** สร้าง Virtual Machine จำลองรันชุดคำสั่งพื้นฐาน (ฝึก CPU & Instruction Sets)

## 6. กลุ่มงาน Automation และการเชื่อมต่อระบบ (Integration & Data)
*เน้นการใช้งานจริงในมุม Business Analyst / Data Analyst*
- **Sheets-to-DB Sync:** ระบบ Sync ข้อมูลจาก Google Sheets ลง MySQL/Pocketbase อัตโนมัติ
- **Web Accessibility Crawler:** บอทสำรวจหน้าเว็บเพื่อหาจุดที่ผิดหลัก Accessibility (ฝึก Web Scraping & DOM Parsing)
- **Automated TOR Tracker:** ตัวดึงข้อมูลจากเอกสาร TOR มาสรุปสถานะลง Dashboard (ฝึก Text Extraction)