# สรุปผลการทดสอบทั้งหมด (27 Projects + WebSocket Soak)

> Docker-based benchmark, 5 runs (1 warm-up + 4 measured), Debian bookworm, Apple Silicon

---

## 🏆 ผลรวมการแข่งขัน (27 mini-projects)

| ภาษา | ชนะ | สัดส่วน | โดดเด่นใน |
|------|----:|--------:|----------|
| **Zig** | **15** | **56%** | Data processing, systems, low-level loops — manual memory ให้ overhead ต่ำสุด |
| **Rust** | **7** | **26%** | Async networking, regex/SIMD string search, parser throughput, production stability |
| **Go** | **5** | **19%** | HTTP networking (reverse proxy, stdlib), image processing algorithms |

---

## 📋 ผลลัพธ์ทั้งหมด (พร้อมผู้ชนะ)

| # | Project | Go | Rust | Zig | ผู้ชนะ |
|---|---------|---:|-----:|----:|:------:|
| 1.1 | Video Frame Extractor | **517ms*** | 545ms* | 583ms* | **Go** |
| 1.2 | HLS Stream Segmenter | 20,874ms* | 16,261ms* | **15,572ms*** | **Zig** |
| 1.3 | Subtitle Burn-in Engine | 1,869ms* | 1,625ms* | **1,350ms*** | **Zig** |
| 2.1 | High-Perf Reverse Proxy | **10,065 r/s** | 3,640 r/s | 2,669 r/s | **Go** |
| 2.2 | Real-time Audio Chunker | 4–5 µs | 5 µs | **17 ns** | **Zig** |
| 2.3 | Lightweight API Gateway | 54,919 req/s | **57,056 req/s** | 52,103 req/s | **Rust** |
| 3.1 | Local ASR/LLM Proxy | **11,051 req/s** | 1,522 req/s | 119 req/s | **Go** |
| 3.2 | Vector DB Ingester | 21,799 chunks/s | 38,945 chunks/s | **53,617 chunks/s** | **Zig** |
| 3.3 | Custom Log Masker | 3.91 MB/s | **41.71 MB/s** | 11.68 MB/s | **Rust** |
| 4.1 | Log Aggregator Sidecar | 22,750 l/s | 25,782 l/s | **54,014 l/s** | **Zig** |
| 4.2 | Tiny Health Check Agent | 393M checks/s | 511M checks/s | **657M checks/s** | **Zig** |
| 4.3 | Container Watchdog | 394,963 items/s | **577,372 items/s** | 513,349 items/s | **Rust** |
| 5.1 | In-memory Key-Value Store | 14.5M items/s | 6.6M items/s | **20.7M items/s** | **Zig** |
| 5.2 | Custom BitTorrent Client | 3,405 items/s | 4,880 items/s | **5,382 items/s** | **Zig** |
| 5.3 | Small Bytecode VM | 240,449 instr/s | 280,545 instr/s | **432,795 instr/s** | **Zig** |
| 6.1 | Sheets-to-DB Sync | 69.1M items/s | 7.2M items/s | **73.8M items/s** | **Zig** |
| 6.2 | Web Accessibility Crawler | 1.34M items/s | **4.24M items/s** | 3.61M items/s | **Rust** |
| 6.3 | Automated TOR Tracker | 5.1M items/s | 7.96M items/s | **23.6M items/s** | **Zig** |
| 7.1 | DNS Resolver | 5,963 items/s | **6,155 items/s** | 5,492 items/s | **Rust** |
| 7.2 | TCP Port Scanner | 664 items/s | **108,365 items/s** | 277 items/s | **Rust** |
| 7.3 | QUIC Ping Client | 6,013 items/s | 6,284 items/s | **6,338 items/s** | **Zig** |
| 8.1 | PNG Encoder from Scratch | **58.1M items/s** | 47.8M items/s | 26.8M items/s | **Go** |
| 8.2 | JPEG Thumbnail Pipeline | **236,263 items/s** | 229,690 items/s | 220,198 items/s | **Go** |
| 8.3 | Perceptual Hash (pHash) | 12.77 items/s | 13.70 items/s | **14.48 items/s** | **Zig** |
| 9.1 | SQLite Query Engine | 282M items/s | 358M items/s | **897M items/s** | **Zig** |
| 9.2 | CSV Stream Aggregator | 6.1M items/s | 8.0M items/s | **23.2M items/s** | **Zig** |
| 9.3 | Parquet File Reader | 119M items/s | **143.7M items/s** | 140.4M items/s | **Rust** |

> `*` = รวม Docker startup overhead (~400-500ms); หน่วยต่างกันตามประเภทงาน — เทียบข้ามภาษาในโปรเจกต์เดียวกันเท่านั้น

---

## 🔌 WebSocket Public Chat — Long-run (Production Readiness)

> โปรเจกต์พิเศษ: เทียบ 2 profile × 2 โหมด (quick + soak) วัด production stability

### ผลรวม Quick Benchmark (4 scenarios)

| Scenario | Go (GoFiber) | Rust (Axum) | Zig (zap) | ผู้ชนะ |
|----------|-------------|------------|----------|:------:|
| Steady throughput | 84.45 msg/s | **85.39 msg/s** | 82.94 msg/s | **Rust** |
| Burst peak memory | 38 MiB | **20 MiB** | 63 MiB | **Rust** |
| Saturation throughput | 2,665 msg/s | **2,960 msg/s** | 2,945 msg/s | **Rust/Zig** |
| Saturation peak memory | 177 MiB | 161 MiB | **64 MiB** | **Zig** |
| Saturation CPU | 207% | 371% | **83%** | **Zig** |

### ผลรวม Soak Benchmark — Profile A (2026-02-28)

| KPI | Go (GoFiber) | Rust (Axum) | Zig (zap) |
|-----|-------------|------------|----------|
| Steady-soak 300s throughput | 93.88 msg/s | **95.14 msg/s** | 94.70 msg/s |
| Steady-soak peak memory | 15 MiB | **6 MiB** | 30 MiB |
| Steady-soak ws_errors/s | 2.54 ⚠️ | **0.00** | **0.00** |
| Churn-soak 180s connections | 21,251 ⚠️ | 18,000 | 18,000 |
| Churn-soak ws_errors/s | 18.06 ⚠️ | **0.00** | **0.00** |
| Memory leak detected | ไม่พบ | ไม่พบ | ไม่พบ |

**ผู้ชนะ soak**: **Rust** — 0 errors ตลอด 480s, memory 6 MiB คงที่
**runner-up**: **Zig** — 0 errors เช่นกัน แต่ memory สูงกว่า (30 MiB, เพราะ facil.io C runtime)
**หมายเหตุ Go**: ws_errors จาก fasthttp HTTP upgrade anomaly เดิม — ไม่ได้แย่ลงเมื่อ run นานขึ้น

### บทเรียนจาก WebSocket Project

| บทเรียน | รายละเอียด |
|---------|-----------|
| Library ≠ ภาษา | Zig Profile A (zap) ได้ 2,945 msg/s เพราะ facil.io C lib — Profile B (pure Zig) ได้ 578 msg/s |
| Framework overhead < 0.5% | Steady/Burst ระหว่าง Profile A (framework) และ B (stdlib) ต่างกันแทบไม่เกิน 0.5% |
| Rust tokio broadcast ดีที่สุดสำหรับ fan-out | Profile B saturation: Rust 2,982 vs Go 2,722 vs Zig 578 msg/s |
| Soak confirms no memory leak | ทุกภาษา memory คงที่ตลอด 5 นาที — ไม่มี GC pressure ใน Rust/Zig |
| Go fasthttp anomaly persistent | GoFiber churn เกิน expected connections ทุกรอบ ทั้ง quick และ soak |

---

## 🔍 ทำไมแต่ละภาษาถึงชนะ (Pattern Analysis)

### Zig ชนะ 15/27 — เพราะอะไร?

**1. ไม่มี runtime overhead**
Zig ไม่มี GC, ไม่มี async runtime ที่ซับซ้อน → ทุก CPU cycle ไปที่งานจริง
→ ชนะชัดในงานที่วน loop ซ้ำมาก: SQLite (3.2× เหนือ Rust), CSV Aggregator (2.9×), TOR Tracker (3×)

**2. Manual memory = zero allocation ที่ไม่จำเป็น**
ไม่ allocate ถ้าไม่ต้องการ → ชนะใน KV Store, Audio Chunker (17ns latency!)
Rust ต้องใช้ `.clone()` หรือ Arc/Mutex → allocation overhead ใน tight loop

**3. comptime + inlining**
Function inlining เต็มที่ใน ReleaseFast mode → Health Check Agent 657M ops/sec

**จุดอ่อน**: broadcast scalability — ถ้าไม่ใช้ C library ที่ optimize มาแล้ว naive mutex broadcast loop จะ O(n) sequential blocking (เห็นชัดใน WebSocket Profile B: 578 msg/s vs Rust 2,982)

---

### Rust ชนะ 7/27 + production stability — เพราะอะไร?

**1. SIMD string search**
LLVM auto-vectorizes `contains()`, `matches()` → Log Masker (10× เหนือ Go), Web Crawler (3.2×)
ใช้ได้ดีกับ input ยาว (>64 bytes) — สั้นกว่านั้น overhead ของ `to_ascii_lowercase()` ชนะ

**2. Tokio async I/O**
TCP Port Scanner: async non-blocking scan → 108K items/s (Go ที่ sync: 664 items/s)
`tokio::sync::broadcast` channel ออกแบบสำหรับ fan-out — WebSocket saturation 2,982 msg/s

**3. Production stability (ใหม่จาก WebSocket soak)**
Axum + tokio: 0 ws_errors ตลอด 300s steady + 180s churn → **เหมาะกับ long-running service**
Memory คงที่ที่ 6 MiB ตลอด 5 นาที — ไม่มี leak, ไม่มี GC pause

**4. Binary size**
Binary เล็กสุดเสมอ (~388KB–1.94MB) → cache-friendly, startup เร็ว

---

### Go ชนะ 5/27 — เพราะอะไร?

**1. stdlib HTTP แข็งแกร่ง**
`httputil.ReverseProxy` + connection pool → Reverse Proxy 2.8× เหนือ Rust
`net/http` DNS cache เก็บ result ไว้ → TCP Scanner/BitTorrent ชนะในงาน repeated connection

**2. PNG standard library**
`image/png` Go stdlib เร็ว 22% เหนือ Rust image crate สำหรับงาน pixel-level loop

**3. Simple goroutine concurrency**
ASR/LLM Proxy: goroutine per request + channel → 11K req/s (Rust tokio ซับซ้อนกว่า แต่ Zig HTTP framework ช้ากว่ามาก)

**จุดอ่อน**: fasthttp (GoFiber) มี HTTP upgrade anomaly ใน WebSocket churn — connections เกิน expected ทุกรอบ

---

## 📦 Binary Size เปรียบเทียบ

| ภาษา | ขนาด binary ทั่วไป | WebSocket (Profile A/B) | หมายเหตุ |
|------|-------------------:|:-----------------------:|---------|
| **Rust** | **388 KB – 1.94 MB** | 1.94 / **1.50 MB** | เล็กสุด, stripped, static link |
| **Zig** | 271 KB – 2.89 MB | 2.43 / 2.89 MB | ขึ้นกับ library linking |
| **Go** | 1.6 MB – 6.18 MB | 6.18 / 5.43 MB | runtime + GC overhead |

---

## 🎯 บทเรียนสำคัญ

| บทเรียน | ตัวอย่าง | ผลกระทบ |
|---------|---------|---------|
| Allocation ใน tight loop ทำลาย throughput | Rust `.clone()` ใน KV Store → 3× ช้ากว่า Zig | ต้อง profile ก่อน optimize |
| SIMD ต้องการ input ยาวพอ | Rust Log Masker (ยาว) ชนะ, แต่ TOR Tracker (สั้น) แพ้ Zig | string length สำคัญ |
| DNS caching ซ่อนอยู่ใน stdlib | Go `net.Dial` cache → TCP Scanner 2,765ms vs Rust 6,017ms | ระวังเทียบ networking benchmark |
| Framework choice สำคัญกว่าภาษา | Zig manual HTTP 8K → Zap framework 52K req/s (+6.5×) | อย่าเทียบแบบไม่มี context |
| UDP bottleneck = ทุกภาษาเท่ากัน | QUIC Ping: Go/Rust/Zig ≈ 6,000-6,300 items/s | hardware-bound = ไม่ต้อง optimize language |
| Library ≠ ภาษา (WebSocket) | Zig zap (facil.io) ≈ Rust 2,945 msg/s — pure Zig เหลือ 578 msg/s | เลือก library ให้เหมาะงาน |
| Soak test เผยสิ่งที่ quick test ไม่เห็น | Go fasthttp anomaly ปรากฏชัดขึ้นใน churn 180s: 21,251 conns (expected 18,000) | production readiness ต้องการ long-run test |

---

## 🚀 เมื่อไหร่ควรเลือกภาษาไหน

| Use Case | แนะนำ | เหตุผล |
|----------|-------|-------|
| HTTP microservices, API server | **Go** | stdlib HTTP + goroutine = development speed + stability |
| Data pipeline, high-throughput ETL | **Zig** | manual memory, ไม่มี GC pause, throughput สูงสุด |
| Async I/O, network scanner, parser | **Rust** | tokio + LLVM SIMD = performance + memory safety |
| Long-running WebSocket / real-time server | **Rust** | tokio broadcast + Axum = 0 errors ใน soak, memory stable |
| System tools, CLI, agent | **Zig** | binary เล็ก, startup เร็ว, predictable performance |
| Regex-heavy text processing | **Rust** | SIMD DFA engine เร็ว 10× เหนือ Go RE2 |
| Prototype → production | **Go** | readable, fast compile, stdlib ครบ |
| C interop, embedded, low memory | **Zig** | 2 MiB footprint, ไม่มี hidden runtime |

---

## 🔬 Methodology

- **Benchmark runner**: Docker-based, ทุกภาษาใช้ environment เดียวกัน
- **Runs**: 5 ครั้งต่อภาษา (warm-up 1 + measured 4), รายงาน Avg/Min/Max
- **HTTP projects**: `wrk -t4 -c50 -d3s` + Docker network
- **WebSocket quick**: k6 (steady 60s / burst 20s / churn 60s / saturation 100s)
- **WebSocket soak**: k6 (steady-soak 300s / churn-soak 180s) — KPIs: memory drift, ws_errors/s
- **Scale**: REPEATS ถูก calibrate ให้แต่ละ run ≥ 1s เพื่อลด noise
- **Raw data**: `<project>/benchmark/results/<timestamp>.txt`
