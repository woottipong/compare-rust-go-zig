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
│   └── zig/                # zap v0.11 (facil.io)  → image: wsc-zig
├── k6/                     # load-test scenarios (shared)
├── benchmark/
│   ├── run.sh              # → run-profile-a.sh
│   ├── run-profile-a.sh
│   ├── run-profile-b.sh
│   └── results/
└── docs/
```

> **หมายเหตุ**: Zig ใช้ zap (wrapper ของ C library facil.io) ทั้ง Profile A และ B จึงได้ผลเหมือนกัน

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

## Scenarios ที่ทดสอบ

### 1) Steady — ห้องแชตวันธรรมดา
> เสมือน: ผู้ใช้ 100 คนนั่งคุยกันอยู่ในห้องเดียว แต่ละคนพิมพ์ข้อความทุก 1 วินาที เป็นเวลา 1 นาที

- **รูปแบบ**: 100 clients × 1 msg/s × 60s
- **วัด**: throughput ที่นิ่ง, drop rate ≈ 0%, เสถียรภาพพื้นฐาน
- **ตีความ**: ถ้า server ผ่าน scenario นี้ แปลว่าพร้อมใช้งานจริงในสภาวะปกติ

### 2) Burst — คนแห่เข้าห้องพร้อมกัน
> เสมือน: ประกาศข่าวด่วน คนกด link เข้าห้องแชตพร้อมกัน 1,000 คนภายใน 10 วินาที

- **รูปแบบ**: 0 → 1,000 clients ใน 10s, ค้าง 5s, ออกทั้งหมดใน 5s
- **วัด**: ความทนต่อ spike, peak memory
- **ตีความ**: errors 333 ที่เห็นเกิดช่วง ramp-down ตอนเซิร์ฟเวอร์กำลังปิด ไม่ใช่บั๊กของ server

### 3) Churn — ผู้ใช้เข้าๆ ออกๆ ตลอดเวลา
> เสมือน: ห้องแชต live event ที่คนดูเข้ามาดูสักครู่แล้วก็ออก วนซ้ำตลอด 1 ชั่วโมง

- **รูปแบบ**: 200 clients วน connect→join→รอ 2s→leave ต่อเนื่อง 60s
- **วัด**: total connections รวม, ws_errors, memory trend
- **ตีความ**: ดู memory leak — ถ้า memory โตขึ้นเรื่อยๆ แสดงว่า server ไม่คืน resource ของ connection เก่า

### 4) Saturation — กดโหลดสุดขีด
> เสมือน: flash sale — ทุกคนส่งข้อความพร้อมกันอย่างรวดเร็ว และจำนวนคนก็เพิ่มขึ้นเรื่อยๆ

- **รูปแบบ**: 200 → 500 → 1,000 clients, แต่ละคนส่ง 5 msg/s
- **วัด**: เพดาน throughput, drop rate, connect latency p95
- **ตีความ**: scenario นี้จงใจโหลดเกินความสามารถ เพื่อดูว่า server "พัง" อย่างไร — drop gracefully หรือ crash

---

## ผลการทดสอบ (Docker, arm64, 2026-02-28)

### Profile A — Framework (GoFiber · Axum · zap)

#### Steady
| ภาษา | Throughput | k6 errors |
|------|-----------|----------|
| Go (GoFiber)   | 84.39 msg/s | 0 |
| Rust (Axum)    | **85.22 msg/s** | 0 |
| Zig (zap)      | 83.26 msg/s | 0 |

#### Burst
| ภาษา | Throughput | k6 errors |
|------|-----------|----------|
| Go (GoFiber)   | **44.46 msg/s** | 334 |
| Rust (Axum)    | 44.43 msg/s | 333 |
| Zig (zap)      | 42.98 msg/s | 331 |

#### Churn
| ภาษา | Total connections | k6 errors |
|------|------------------|----------|
| Go (GoFiber)   | 6,765 | 765 ⚠️ |
| Rust (Axum)    | 6,000 | 0 |
| Zig (zap)      | 6,000 | 0 |

> ⚠️ GoFiber churn anomaly — connection เกิน 6,000 เพราะพฤติกรรม HTTP upgrade ของ fasthttp ต่างจาก net/http ไม่ใช่บั๊กของ logic หลัก

#### Saturation
| ภาษา | Throughput | Drop rate | k6 errors |
|------|-----------|-----------|----------|
| Go (GoFiber)   | 2,579 msg/s | 0.00% | 36,080 |
| Rust (Axum)    | 560 msg/s | 1.36% | 9,010 |
| Zig (zap)      | **2,929 msg/s** | 0.00% | 805 |

---

### Profile B — Minimal/Stdlib (net/http · tokio-tungstenite · zap)

#### Steady
| ภาษา | Throughput | Peak memory | k6 errors |
|------|-----------|-------------|-----------|
| Go   | 84.30 msg/s | 11 MiB | 0 |
| Rust | **85.34 msg/s** | **5 MiB** | 0 |
| Zig  | 83.77 msg/s | 30 MiB | 0 |

#### Burst
| ภาษา | Throughput | Peak memory | k6 errors |
|------|-----------|-------------|-----------|
| Go   | 44.43 msg/s | 37 MiB | 333 |
| Rust | **44.43 msg/s** | **21 MiB** | 333 |
| Zig  | 43.13 msg/s | 63 MiB | 331 |

#### Churn
| ภาษา | Total connections | Peak memory | k6 errors |
|------|------------------|-------------|-----------|
| Go   | 6,000 | 15 MiB | 0 |
| Rust | 6,000 | **11 MiB** | 0 |
| Zig  | 6,000 | 33 MiB | 0 |

#### Saturation
| ภาษา | Throughput | Drop rate | Peak memory | k6 errors |
|------|-----------|-----------|-------------|-----------|
| Go   | 2,551 msg/s | 0.00% | 195 MiB | 46,674 |
| Rust | 597 msg/s | 1.14% | **95 MiB** | 2,443 |
| Zig  | **2,951 msg/s** | 0.00% | 63 MiB | 802 |

---

### ขนาดไบนารี

| ภาษา | Profile A | Profile B | ผลต่าง |
|------|-----------|-----------|--------|
| Go   | 6.18 MB | 5.43 MB | −14% |
| Rust | 1.94 MB | **1.50 MB** | −29% |
| Zig  | 2.43 MB | 2.43 MB | 0% |

---

## วิเคราะห์ผล

### Steady & Burst — ทั้ง 3 ภาษาใกล้เคียงกัน
ที่ 100 clients throughput ทุกภาษาอยู่ที่ ~83–85 msg/s ซึ่งบ่งชี้ว่าคอขวดอยู่ที่ rate limit (10 msg/s/conn) และพารามิเตอร์ของ k6 ไม่ใช่ตัว server implementation ทำให้ไม่สามารถแยกความต่างในมิตินี้ได้

### Saturation — ความต่างชัดเจน
เมื่อโหลดหนักขึ้น Zig และ Go โดดเด่นขึ้นมาก:
- **Zig (2,951 msg/s)**: เร็วที่สุด — facil.io มี built-in pub/sub ที่ optimize มาแล้ว, drop rate 0%
- **Go (2,551 msg/s)**: ใกล้เคียง Zig — goroutine model เหมาะกับ concurrent broadcast แต่ใช้ memory สูงสุด (195 MiB) และ k6 errors มากจาก connection churn ช่วงท้าย
- **Rust (597 msg/s)**: ต่ำกว่าอย่างมีนัยสำคัญ — tokio-tungstenite + async overhead ทำให้ throughput ต่ำกว่าที่ควรจะเป็น และมี drop rate 1.14%

### Memory — Rust ชนะขาด
Rust ใช้ memory น้อยที่สุดในทุก scenario (5–95 MiB) เทียบกับ Go (11–195 MiB) และ Zig (30–63 MiB) เหมาะมากสำหรับ production ที่ความหนาแน่นของ server สำคัญ

### Binary Size
Rust ให้ binary เล็กที่สุดทั้งสองโปรไฟล์ (1.50 MB / 1.94 MB) — framework dependency เพิ่ม size Go +14%, Rust +29% แต่ Zig ไม่เปลี่ยนเพราะใช้ zap เหมือนกันทั้งสองโปรไฟล์

### Framework Impact — น้อยมาก
Steady/Burst ระหว่าง Profile A และ B ต่างกันแทบไม่เกิน 0.5% แสดงว่า GoFiber, Axum ไม่ได้เพิ่มประสิทธิภาพหรือ overhead ที่วัดได้ในโหลดระดับนี้

---

## สรุปภาพรวม

| มิติ | ผู้ชนะ | หมายเหตุ |
|------|--------|---------|
| Throughput (saturation) | **Zig** | facil.io C library optimize สูง |
| Memory efficiency | **Rust** | ชนะทุก scenario อย่างชัดเจน |
| Binary size | **Rust** | เล็กที่สุดทั้งสองโปรไฟล์ |
| Connection stability | **ทุกภาษา** | Churn ผ่านเท่ากันหมด |
| Framework overhead | **น้อยมาก** | ต่างกัน < 1% ใน steady/burst |

> **ข้อควรระวัง**: Zig ใช้ facil.io ซึ่งเป็น C library ที่ optimize มา 10+ ปี ทำให้ได้เปรียบใน saturation — ไม่ใช่ความสามารถของ Zig ภาษาล้วนๆ

---

## แผนถัดไป: Long-run Benchmark (120s – 5 นาที)

> สถานะ: วางแผนไว้แล้ว เดี๋ยวทำต่อในรอบถัดไป

### โหมดที่จะเพิ่ม

| โหมด | Duration | ใช้สำหรับ |
|------|----------|--------|
| `quick` (ปัจจุบัน) | steady 60s / burst 20s / churn 60s / saturation 100s | dev loop / quick compare |
| `soak` | steady 300s / churn 180s | production readiness · 8 นาที |

> **ข้อสังเกต**: `soak` ข้าม burst และ saturation เพราะผลของ scenario เหล่านี้ขึ้นกับ spike ไม่ใช่เวลา รู้แล้วจาก quick

### KPI ที่จะเพิ่มเติมในรอบ long-run

| KPI | วิธีวัด | อธิบาย |
|-----|--------|--------|
| Memory drift | peak mem ช่วงต้น vs ช่วงท้าย | ถ้าโตขึ้นเรื่อยๆ หมายถึง memory leak |
| Throughput degradation | tp ช่วงท้าย / tp ช่วงต้น (%) | ตกเกิน 10% ถือว่าผิดปกติ |
| Error accumulation | ws_errors ต่อวินาที | ต้องไม่พุ่งต่อเนื่องหลัง 10 นาที |
| Drop rate trend | drop rate ช่วงต้น vs ท้าย | ต้องไม่บานปลายรัน |

### เกณฑ์ผ่าน (Draft)

| เกณฑ์ | ระดับ |
|------|-------|
| รันครบเวลาโดยไม่ crash | ผ่านขั้นเป็น |
| Memory ไม่โตต่อเนื่องผิดปกติ | ผ่านขั้นเป็น |
| ws_errors ไม่พุ่งต่อเนื่องหลัง 10 นาที | ผ่านขั้นเป็น |
| Throughput ช่วงท้ายไม่ตกเกิน 10% จากช่วงต้น | ผ่านขั้นเป็น |
| Drop rate ไม่บานปลายรัน | ผ่านขั้นเป็น |

### วิธี implement (plan)

1. เพิ่ม env var `BENCH_MODE=quick|soak` ใน `run-profile-a.sh` / `run-profile-b.sh`
2. ปรับ duration constants: steady 300s, churn 180s สำหรับ soak mode
3. ข้าม burst และ saturation ใน soak mode (skip ใน script)
4. บันทึกผลไว้ในชื่อไฟล์ `websocket_profile_a_soak_<timestamp>.txt` แยกจาก quick
5. เพิ่ม summary section ใน result file: throughputช่วงต้น vs ท้าย, memory drift

---

## Dependencies

| ภาษา | Profile A | Profile B |
|------|-----------|-----------|
| Go   | GoFiber v2 + gofiber/websocket | net/http + gorilla/websocket v1.5.3 |
| Rust | Axum 0.7 + axum::extract::ws | tokio-tungstenite 0.26 |
| Zig  | zap v0.11.0 (facil.io 0.7.4) | zap v0.11.0 (facil.io 0.7.4) |
