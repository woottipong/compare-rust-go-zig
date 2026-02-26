# Compare Rust / Go / Zig — Master Plan

## ภาพรวมสถานะ

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
| 5.1 | In-memory Key-Value Store | ✅ | 14,549,643 items/s | 6,589,801 items/s | 20,747,797 items/s |
| 5.2 | Custom BitTorrent Client | ✅ | 3,405 items/s | 4,880 items/s | 5,382 items/s |
| 5.3 | Small Bytecode VM | ✅ | 240,449 instr/s | 280,545 instr/s | 432,795 instr/s |
| 6.1 | Sheets-to-DB Sync | ✅ | 69,121,538 items/s | 7,248,737 items/s | 73,838,600 items/s |
| 6.2 | Web Accessibility Crawler | ✅ | 1,339,630 items/s | 4,237,100 items/s | 3,606,971 items/s |
| 6.3 | Automated TOR Tracker | ✅ | 4,742,942 items/s | 6,755,853 items/s | 15,810,537 items/s |
| 7.1 | DNS Resolver | ✅ | 5,963 items/s | 6,155 items/s | 5,492 items/s |
| 7.2 | TCP Port Scanner | ✅ | 664 items/s | 108,365 items/s | 277 items/s |
| 7.3 | QUIC Ping Client | ✅ | 6,013 items/s | 6,284 items/s | 6,338 items/s |
| 8.1 | PNG Encoder from Scratch | ✅ | 58,142,585 items/s | 47,791,195 items/s | 26,833,474 items/s |
| 8.2 | JPEG Thumbnail Pipeline | ✅ | 236,263 items/s | 229,690 items/s | 220,198 items/s |
| 8.3 | Perceptual Hash (pHash) | ✅ | 12.77 items/s | 13.70 items/s | 14.48 items/s |
| 9.1 | SQLite Query Engine (subset) | ✅ | 282,688,842 items/s | 358,383,573 items/s | 897,198,108 items/s |
| 9.2 | CSV Stream Aggregator | ✅ | 6,062,819 items/s | 8,003,336 items/s | 23,183,717 items/s |
| 9.3 | Parquet File Reader | ✅ | 119,200,833 items/s | 143,730,005 items/s | 140,448,514 items/s |

> หมายเหตุ: ค่า `*` หมายถึงผล benchmark ที่มี Docker container startup overhead รวมอยู่ด้วย

## วัตถุประสงค์การทดสอบแต่ละกลุ่ม

| Group | Theme | วัตถุประสงค์หลัก |
|---|---|---|
| 1 | Video & Media Processing | วัดประสิทธิภาพงาน media pipeline ที่มี FFmpeg/C interop, decode/encode และ file streaming |
| 2 | Infrastructure & Networking | เทียบ concurrency model และ network stack ในงาน proxy/gateway/low-latency streaming |
| 3 | AI & Data Pipeline | วัด throughput งานเตรียมข้อมูล AI, queue processing, parsing และ string masking |
| 4 | DevOps Tools | เทียบความเร็วและความประหยัดทรัพยากรในงาน sidecar/agent แบบ long-running |
| 5 | Systems Fundamentals | วัด data-structure/algorithm overhead ในงาน memory store, protocol และ VM execution |
| 6 | Integration & Data | เทียบงานเชื่อมระบบจริง เช่น sync, crawling, text extraction และ transformation |
| 7 | Low-Level Networking | วัดประสิทธิภาพ socket-level I/O, timeout handling และ protocol parsing ระดับต่ำ |
| 8 | Image Processing (Zero-dependency) | เทียบ pure algorithm performance โดยลดผลกระทบจาก library abstraction |
| 9 | Data Engineering Primitives | วัด streaming throughput, columnar decoding และ file-format parsing ข้อมูลขนาดใหญ่ |


## Progress by Group

| Group | Theme | Projects | Status |
|---|---|---|---|
| 1 | Video & Media Processing | video-frame-extractor, hls-stream-segmenter, subtitle-burn-in-engine | ✅ 3/3 |
| 2 | Infrastructure & Networking | high-perf-reverse-proxy, realtime-audio-chunker, lightweight-api-gateway | ✅ 3/3 |
| 3 | AI & Data Pipeline | local-asr-llm-proxy, vector-db-ingester, custom-log-masker | ✅ 3/3 |
| 4 | DevOps Tools | log-aggregator-sidecar, tiny-health-check-agent, container-watchdog | ✅ 3/3 |
| 5 | Systems Fundamentals | in-memory-kv-store, custom-bittorrent-client, small-bytecode-vm | ✅ 3/3 |
| 6 | Integration & Data | sheets-to-db-sync, web-accessibility-crawler, automated-tor-tracker | ✅ 3/3 |
| 7 | Low-Level Networking | dns-resolver, tcp-port-scanner, quic-ping-client | ✅ 3/3 |
| 8 | Image Processing (Zero-dependency) | png-encoder-from-scratch, jpeg-thumbnail-pipeline, perceptual-hash-phash | ✅ 3/3 |
| 9 | Data Engineering Primitives | sqlite-query-engine, csv-stream-aggregator, parquet-file-reader | ✅ 3/3 |

## Highlights (Short)

- **Go** เด่นในงาน networking/runtime ที่อาศัย stdlib โดยตรง (เช่น reverse proxy)
- **Rust** เด่นในงาน async + parser/regex throughput สูง
- **Zig** เด่นในงาน data/system ที่ต้องการ low overhead และ manual memory

---

## Executive Summary

- ✅ Completed: **27/27 projects** (9 groups)
- ✅ Languages covered per project: **Go + Rust + Zig**
- ✅ Benchmark policy: **Docker-based**; results saved under each project's `benchmark/results/`
- ✅ Documentation policy: each project has its own `README.md` with setup, benchmark, and results

## สรุปเชิงเทคนิค

1. **Go** เด่นด้าน networking ที่ใช้ stdlib/runtime ได้ตรงจุด (เช่น reverse proxy)
2. **Rust** เด่นด้าน throughput ที่ต้องใช้ async + parser/regex ที่มีประสิทธิภาพสูง
3. **Zig** เด่นด้านงาน data/system ที่ได้ประโยชน์จาก manual memory และ low-overhead runtime

## หมายเหตุการอ่านผล

- ตัวเลขในตารางด้านบนคือผล benchmark ที่ใช้เปรียบเทียบข้ามภาษาในแต่ละโจทย์
- หน่วยของผลลัพธ์ต่างกันตามประเภทงาน (เช่น ms, req/s, items/s, MB/s, instr/s) จึงควรเทียบข้ามภาษาในโจทย์เดียวกัน
- สำหรับรายละเอียดวิธีวัด/ค่าเฉลี่ย/ขนาด binary ให้ดู `README.md` ของแต่ละโปรเจกต์
- กลับไปภาพรวม repository: [`README.md`](./README.md)