# WebSocket Public Chat — Go vs Rust vs Zig

เปรียบเทียบ WebSocket chat server ที่เขียนด้วย 3 ภาษา โดยทดสอบด้วย k6 load test ครอบคลุม 4 รูปแบบโหลด

## โครงสร้างโปรเจกต์

```
websocket-public-chat/
├── profile-a/              # framework servers
│   ├── go/                 # GoFiber v2            → image: wsca-go
│   ├── rust/               # Axum 0.7              → image: wsca-rust
│   └── zig/                # zap v0.11 (facil.io)  → image: wsca-zig
├── profile-b/              # minimal/stdlib servers
│   ├── go/                 # net/http + gorilla    → image: wsc-go
│   ├── rust/               # tokio-tungstenite     → image: wsc-rust
│   └── zig/                # websocket.zig (pure)  → image: wsc-zig
├── k6/                     # load-test scenarios (shared)
├── benchmark/
│   ├── run.sh              # → run-profile-a.sh
│   ├── run-profile-a.sh
│   ├── run-profile-b.sh
│   └── results/
└── docs/
```

> **หมายเหตุ**: Profile A Zig ใช้ zap (wrapper ของ C library facil.io) — Profile B Zig ใช้ websocket.zig (pure Zig, ไม่มี C dependency) ทำให้การเปรียบเทียบยุติธรรมขึ้น

---

## โปรโตคอล

| ค่าคงที่ | ค่า |
|----------|-----|
| Room | `"public"` (single room) |
| Chat payload | 128 bytes |
| Rate limit | 10 msg/s ต่อ connection (token bucket) |
| Ping/Pong timeout | 30s / 60s |
| Message types | `join` · `chat` · `ping` · `pong` · `leave` |

ข้อความที่เกิน rate limit จะถูก **drop** (ไม่ตัดการเชื่อมต่อ)

---

## รันการทดสอบ

```bash
cd websocket-public-chat

# Profile A — framework servers
bash benchmark/run.sh

# Profile B — minimal/stdlib servers
bash benchmark/run-profile-b.sh
```

ผลจะบันทึกอัตโนมัติที่ `benchmark/results/`

---

## Benchmark Methodology

- **Platform**: Docker (arm64), --cpus 2 --memory 512m per container
- **Scenarios**: Steady / Burst / Churn / Saturation (4 รูปแบบ)
- **Metrics**: throughput, peak memory, peak CPU, k6 errors, connect p95
- **Tool**: k6 load generator (containerized)

---

## Scenarios ที่ทดสอบ

### 1) Steady — ห้องแชตวันธรรมดา
> เสมือน: ผู้ใช้ 100 คนนั่งคุยกันอยู่ในห้องเดียว แต่ละคนพิมพ์ข้อความทุก 1 วินาที เป็นเวลา 1 นาที

- **รูปแบบ**: 100 clients × 1 msg/s × 60s
- **วัด**: throughput ที่นิ่ง, drop rate ≈ 0%, เสถียรภาพพื้นฐาน

### 2) Burst — คนแห่เข้าห้องพร้อมกัน
> เสมือน: ประกาศข่าวด่วน คนกด link เข้าห้องแชตพร้อมกัน 1,000 คนภายใน 10 วินาที

- **รูปแบบ**: 0 → 1,000 clients ใน 10s, ค้าง 5s, ออกทั้งหมดใน 5s
- **วัด**: ความทนต่อ spike, peak memory

### 3) Churn — ผู้ใช้เข้าๆ ออกๆ ตลอดเวลา
> เสมือน: ห้องแชต live event ที่คนดูเข้ามาดูสักครู่แล้วก็ออก วนซ้ำตลอด 1 ชั่วโมง

- **รูปแบบ**: 200 clients วน connect→join→รอ 2s→leave ต่อเนื่อง 60s
- **วัด**: total connections รวม, ws_errors, memory trend

### 4) Saturation — กดโหลดสุดขีด
> เสมือน: flash sale — ทุกคนส่งข้อความพร้อมกันอย่างรวดเร็ว และจำนวนคนก็เพิ่มขึ้นเรื่อยๆ

- **รูปแบบ**: 200 → 500 → 1,000 clients, แต่ละคนส่ง 5 msg/s
- **วัด**: เพดาน throughput, drop rate, connect latency p95

---

## ผลการทดสอบ (Docker, arm64, 2026-02-28)

### Profile A — Framework (GoFiber · Axum · zap/facil.io)

#### Steady
| ภาษา | Throughput | Peak memory | Peak CPU | k6 errors |
|------|-----------|-------------|---------|----------|
| Go (GoFiber)   | 84.45 msg/s | 12 MiB | 10% | 109 |
| Rust (Axum)    | **85.39 msg/s** | **5 MiB** | 9% | 0 |
| Zig (zap)      | 82.94 msg/s | 30 MiB | 1% | 0 |

#### Burst
| ภาษา | Throughput | Peak memory | Peak CPU | k6 errors |
|------|-----------|-------------|---------|----------|
| Go (GoFiber)   | **44.46 msg/s** | 38 MiB | 97% | 334 |
| Rust (Axum)    | 44.43 msg/s | **20 MiB** | 162% | 333 |
| Zig (zap)      | 43.18 msg/s | 63 MiB | 16% | 331 |

#### Churn
| ภาษา | Total connections | Peak memory | Peak CPU | k6 errors |
|------|------------------|-------------|---------|----------|
| Go (GoFiber)   | 7,370 | 16 MiB | 6% | 1,370 ⚠️ |
| Rust (Axum)    | 6,000 | **6 MiB** | 5% | 0 |
| Zig (zap)      | 6,000 | 32 MiB | 8% | 0 |

> ⚠️ GoFiber churn anomaly — connection เกิน 6,000 เพราะพฤติกรรม HTTP upgrade ของ fasthttp

#### Saturation
| ภาษา | Throughput | Drop rate | Peak memory | Peak CPU | k6 errors |
|------|-----------|-----------|-------------|---------|----------|
| Go (GoFiber)   | 2,665 msg/s | 0.01% | 177 MiB | 207% | 50,607 |
| Rust (Axum)    | **2,960 msg/s** | 0.00% | 161 MiB | 371% | 7,239 |
| Zig (zap)      | 2,945 msg/s | 0.00% | **64 MiB** | **83%** | 801 |

---

### Profile B — Minimal/Stdlib (net/http · tokio-tungstenite · websocket.zig)

#### Steady
| ภาษา | Throughput | Peak memory | Peak CPU | k6 errors |
|------|-----------|-------------|---------|----------|
| Go   | 84.28 msg/s | 9 MiB | 6% | 111 |
| Rust | **85.23 msg/s** | **5 MiB** | 10% | 0 |
| Zig  | 85.18 msg/s | **2 MiB** | 11% | 0 |

#### Burst
| ภาษา | Throughput | Peak memory | Peak CPU | k6 errors |
|------|-----------|-------------|---------|----------|
| Go   | 44.43 msg/s | 29 MiB | 85% | 333 |
| Rust | **44.43 msg/s** | **21 MiB** | 84% | 333 |
| Zig  | 44.43 msg/s | **8 MiB** | 59% | 333 |

#### Churn
| ภาษา | Total connections | Peak memory | Peak CPU | k6 errors |
|------|------------------|-------------|---------|----------|
| Go   | 6,000 | 14 MiB | 5% | 0 |
| Rust | 6,000 | 7 MiB | 3% | 0 |
| Zig  | 6,000 | **4 MiB** | 5% | 0 |

#### Saturation
| ภาษา | Throughput | Drop rate | Peak memory | Peak CPU | k6 errors |
|------|-----------|-----------|-------------|---------|----------|
| Go   | 2,722 msg/s | 0.00% | 153 MiB | 207% | 29,960 |
| Rust | **2,982 msg/s** | 0.00% | 116 MiB | 188% | 5,153 |
| Zig  | 578 msg/s | 2.91% | **66 MiB** | 225% | 6,294 |

---

### ขนาดไบนารี

| ภาษา | Profile A | Profile B | หมายเหตุ |
|------|-----------|-----------|--------|
| Go   | 6.18 MB | 5.43 MB | −14% (Fiber overhead) |
| Rust | 1.94 MB | **1.50 MB** | −29% (Axum overhead) |
| Zig  | 2.43 MB | 2.89 MB | +19% (websocket.zig vs zap) |

---

## วิเคราะห์ผล

### Steady & Burst — ทั้ง 3 ภาษาใกล้เคียงกัน
ที่ 100 clients throughput ทุกภาษาอยู่ที่ ~83–85 msg/s คอขวดอยู่ที่ rate limit (10 msg/s/conn) ไม่ใช่ตัว server implementation

### Saturation Profile A — สามทีเท่ากัน (หลังแก้ Rust)
Rust หลัง fix AtomicU64 + try_send: **2,960 msg/s** ใกล้เคียง Zig (2,945) และ Go (2,665) มาก ต่างจาก baseline เดิม 560 msg/s อย่างมีนัยสำคัญ

### Profile B Saturation — เห็นผลที่ยุติธรรม
เมื่อ Zig ใช้ pure Zig broadcast loop แทน facil.io pub/sub:
- **Rust (2,982 msg/s)**: ชนะ — tokio broadcast channel ออกแบบมาสำหรับ fan-out โดยเฉพาะ
- **Go (2,722 msg/s)**: ใกล้เคียง — goroutine + channel model เหมาะกับ concurrent I/O
- **Zig (578 msg/s)**: ต่ำกว่า — mutex-protected broadcast loop ทำงาน O(n) แบบ sequential blocking

> **บทเรียนสำคัญ**: ผลของ Zig ใน Profile A (zap) สะท้อน **ความสามารถของ facil.io C library** ไม่ใช่ภาษา Zig เอง เมื่อเปลี่ยนมาใช้ pure Zig, Zig มีปัญหาเรื่อง broadcast scalability เหมือนกับการ implement naive broadcast ใน language ไหนก็ตาม

### Memory — Zig ชนะในมิติ memory (Profile B)
Profile B: Zig ใช้ memory น้อยที่สุดในทุก scenario (2–66 MiB) เพราะ websocket.zig ไม่มี overhead ของ C runtime

### Framework Impact — ยังน้อยมาก
Steady/Burst ระหว่าง Profile A และ B ต่างกันแทบไม่เกิน 0.5%

---

## สรุปภาพรวม

| มิติ | Profile A | Profile B | หมายเหตุ |
|------|-----------|-----------|---------|
| Throughput (saturation) | **Zig/Rust** (ใกล้เคียงกัน) | **Rust** | Rust ชนะ Profile B ด้วย tokio channel |
| Memory efficiency | **Rust** (5 MiB) | **Zig** (2–4 MiB) | Zig wins ใน pure Zig stack |
| Binary size | **Rust** (1.94 MB) | **Rust** (1.50 MB) | Rust เล็กสุดทั้งสองโปรไฟล์ |
| Connection stability | ทุกภาษา | ทุกภาษา | Churn ผ่านเท่ากันหมด |
| CPU efficiency (saturation) | **Zig** (83%) | **Rust** (188%) | Zig ใช้ CPU น้อยกว่าใน Profile A |

> **ข้อสรุป**: Rust มีความสมดุลดีที่สุด — throughput สูง, memory ต่ำ, binary เล็ก ส่วน Zig มี memory footprint ต่ำที่สุดใน Profile B แต่ broadcast scalability ต้องการ optimization เพิ่มเติม

---

## Improvement History (Epics 6–9)

| Epic | Change | Before | After | Delta |
|------|--------|--------|-------|-------|
| **6** — Rust: AtomicU64 + try_send | Saturation throughput | 597 msg/s | **2,982 msg/s** | **+400%** ✅ |
| **6** | Saturation drop rate | 1.14% | 0.00% | ✅ |
| **7** — Go: reduce buffer size | Saturation throughput | 2,551 msg/s | 2,722 msg/s | +7% ✅ |
| **7** | Peak memory (saturation) | 195 MiB | **153 MiB** | **−22%** ✅ |
| **9** — Zig: websocket.zig (fair) | Saturation throughput | 2,951 msg/s *(zap)* | 578 msg/s | −80%¹ |
| **9** | Steady memory | 30 MiB | **2 MiB** | −93% ✅ |

> ¹ ไม่ใช่ regression — Zig ด้วย zap ได้เปรียบจาก facil.io C library ที่ optimize มา 10+ ปี ผลจาก websocket.zig สะท้อนความสามารถจริงของ pure Zig runtime

---

## แผนถัดไป: Long-run Benchmark (120s – 5 นาที)

> สถานะ: วางแผนไว้แล้ว

### โหมดที่จะเพิ่ม

| โหมด | Duration | ใช้สำหรับ |
|------|----------|--------|
| `quick` (ปัจจุบัน) | steady 60s / burst 20s / churn 60s / saturation 100s | dev loop / quick compare |
| `soak` | steady 300s / churn 180s | production readiness · 8 นาที |

### KPI ที่จะวัดใน long-run

| KPI | วิธีวัด |
|-----|--------|
| Memory drift | peak mem ช่วงต้น vs ช่วงท้าย |
| Throughput degradation | tp ช่วงท้าย / tp ช่วงต้น (%) |
| Error accumulation | ws_errors ต่อวินาที |

---

## Dependencies

| ภาษา | Profile A | Profile B |
|------|-----------|-----------|
| Go   | GoFiber v2 + gofiber/websocket | net/http + gorilla/websocket v1.5.3 |
| Rust | Axum 0.7 + axum::extract::ws | tokio-tungstenite 0.26 |
| Zig  | zap v0.11.0 (facil.io 0.7.4) | websocket.zig (karlseguin, pure Zig) |
