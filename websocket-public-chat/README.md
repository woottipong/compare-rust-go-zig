# WebSocket Public Chat

โปรเจกต์เซิร์ฟเวอร์ห้องแชต WebSocket ที่พัฒนา 3 ภาษา (**Go**, **Rust**, **Zig**) และทำ benchmark ด้วย k6 ตามโปรไฟล์โหลดที่กำหนด

## โครงสร้างไดเรกทอรี

```
websocket-public-chat/
├── profile-b/                    # minimal stdlib servers (benchmarked ✅)
│   ├── go/                       # net/http + gorilla/websocket  → image: wsc-go
│   ├── rust/                     # tokio + tokio-tungstenite     → image: wsc-rust
│   └── zig/                      # zap v0.11 (facil.io)          → image: wsc-zig
├── profile-a/                    # framework servers (benchmarked ✅)
│   ├── go/                       # GoFiber v2 + gofiber/websocket/v2  → image: wsca-go
│   ├── rust/                     # Axum 0.7 + axum::extract::ws       → image: wsca-rust
│   └── zig/                      # zap v0.11 (copy — same framework)  → image: wsca-zig
├── k6/                           # load-test scenarios (shared by both profiles)
│   ├── steady.js                 # 100 VUs × 1 msg/s × 60s
│   ├── burst.js                  # ramp 0→1000 VUs over 10s
│   ├── churn.js                  # 200 VUs × connect→2s→leave
│   ├── saturation.js             # 200→500→1000 VUs × 5 msg/s (finds ceiling)
│   └── Dockerfile
├── benchmark/
│   ├── run.sh                    # wrapper → run-profile-b.sh
│   ├── run-profile-b.sh          # Profile B: wsc-go / wsc-rust / wsc-zig
│   ├── run-profile-a.sh          # Profile A: wsca-go / wsca-rust / wsca-zig
│   └── results/
└── docs/
    ├── protocol.md
    └── decisions.md
```

## โปรโตคอล

| ค่าคงที่ | ค่า |
|----------|-----|
| Room | `"public"` |
| ขนาด chat payload | 128 bytes |
| Rate limit | 10 msg/s ต่อ connection (token bucket) |
| Ping interval | 30 วินาที |
| Pong timeout | 60 วินาที |

ชนิดข้อความ: `join` · `chat` · `ping` · `pong` · `leave`

การจัดการข้อผิดพลาด: ข้อความที่เกิน rate limit จะถูก **drop** (ไม่ตัดการเชื่อมต่อ), ส่วน JSON ที่ไม่ถูกต้องหรือ type ที่ไม่รู้จักจะถูก **ข้ามแบบเงียบๆ**

## วิธี Build และ Run

### รันแบบ Local

```bash
# Go (Profile B)
cd profile-b/go && unset GOROOT && go build -o websocket-public-chat .
./websocket-public-chat --port 8080 --duration 60

# Rust (Profile B)
cd profile-b/rust && cargo build --release
./target/release/websocket-public-chat --port 8080 --duration 60

# Zig (Profile B)
cd profile-b/zig && zig build -Doptimize=ReleaseFast
./zig-out/bin/websocket-public-chat 8080 60
```

### Docker — Profile B

```bash
docker build -t wsc-go   profile-b/go/
docker build -t wsc-rust profile-b/rust/
docker build -t wsc-zig  profile-b/zig/

docker run --rm wsc-go   --port 8080 --duration 60
docker run --rm wsc-rust --port 8080 --duration 60
docker run --rm wsc-zig  8080 60
```

### Docker — Profile A

```bash
docker build -t wsca-go   profile-a/go/
docker build -t wsca-rust profile-a/rust/
docker build -t wsca-zig  profile-a/zig/

docker run --rm wsca-go   --port 8080 --duration 60
docker run --rm wsca-rust --port 8080 --duration 60
docker run --rm wsca-zig  8080 60
```

### รัน Tests

```bash
# Profile B
cd profile-b/go   && go test ./...
cd profile-b/rust && cargo test
cd profile-b/zig  && zig build test

# Profile A
cd profile-a/go   && go test ./...
cd profile-a/rust && cargo test
```

## Benchmark

```bash
cd websocket-public-chat

# Profile B — minimal stdlib (wsc-go / wsc-rust / wsc-zig)
bash benchmark/run.sh            # wrapper → run-profile-b.sh
bash benchmark/run-profile-b.sh  # same, run directly

# Profile A — framework layer (wsca-go / wsca-rust / wsca-zig)
bash benchmark/run-profile-a.sh
```

k6 จะรันแต่ละ scenario กับแต่ละเซิร์ฟเวอร์ตามลำดับ และบันทึกผลอัตโนมัติที่ `benchmark/results/`

สิ่งที่เก็บในแต่ละรอบ:
- **Throughput, drop rate, จำนวน connection (ฝั่ง server)** จากสถิติที่พิมพ์ตอน shutdown
- **Peak memory** จาก `docker stats --no-stream` ระหว่างรัน k6
- **WebSocket connect p95** จาก metric `ws_connect_duration` (ต้องไม่ใช้ `--quiet`)

### คำอธิบายแต่ละ Scenario (Steady / Burst / Churn / Saturation)

ส่วนนี้คือคู่มือสั้นๆ ว่าแต่ละการทดสอบใช้วัดอะไร และควรดูค่าไหนเป็นหลัก

### สรุปแบบสั้น (อ่านเร็ว)

#### Scenario 1: Steady Load
```
100 clients เชื่อมต่อพร้อมกัน
แต่ละ client ส่ง 1 chat/sec
duration: 60 วินาที
วัด: throughput (msg/sec), latency p95, drop rate
```

#### Scenario 2: Burst Connect
```
1000 clients เชื่อมต่อภายใน 10 วินาที
ทุก client ส่ง join แล้วรอ 5 วินาที แล้ว leave
วัด: connection success/error, peak memory
```

#### Scenario 3: Churn
```
200 clients active ต่อเนื่อง
วนลูป: connect -> join -> รอ 2 วินาที -> leave -> reconnect
duration: 60 วินาที
วัด: ความเสถียรของ connect/disconnect, ws_errors, memory trend
```

#### Scenario 4: Saturation
```
ไล่โหลดจาก 200 -> 500 -> 1000 clients
แต่ละ client ส่ง 5 chat/sec
วัด: throughput เพดานสูงสุด, connect p95, peak memory
```

#### 1) Steady
- **รูปแบบโหลด**: 100 VUs, แต่ละ VU ส่ง 1 ข้อความ/วินาที เป็นเวลา 60 วินาที
- **วัตถุประสงค์**: วัดเสถียรภาพพื้นฐานในสภาพการใช้งานปกติ
- **ค่าที่ควรโฟกัส**:
  - Throughput (msg/s) ควรนิ่ง
  - Drop rate ควรใกล้ 0% (ยังไม่ชน rate limit)
  - `ws_errors` ใช้ดูปัญหาเรื่องเชื่อมต่อ/ปิดการเชื่อมต่อ

#### 2) Burst
- **รูปแบบโหลด**: เพิ่มผู้ใช้จาก 0 → 1000 ภายใน 10 วินาที, ค้าง 5 วินาที, แล้วลดลง 5 วินาที
- **วัตถุประสงค์**: วัดความทนต่อโหลดที่พุ่งขึ้นเร็ว
- **ค่าที่ควรโฟกัส**:
  - Throughput ช่วงที่โหลดพุ่ง
  - จำนวนการเชื่อมต่อสูงสุดที่ระบบรับได้
  - `ws_errors` ช่วง ramp-down (มักเกี่ยวกับจังหวะปิดรัน มากกว่าบั๊กหลัก)

#### 3) Churn
- **รูปแบบโหลด**: 200 VUs วนลูป connect → join → รอ 2 วินาที → leave ต่อเนื่อง 60 วินาที
- **วัตถุประสงค์**: stress วงจรชีวิตการเชื่อมต่อ (เปิด/ปิดบ่อย)
- **ค่าที่ควรโฟกัส**:
  - จำนวน connections รวมที่รองรับได้ (KPI หลัก)
  - `ws_errors` เพื่อจับสัญญาณปัญหา lifecycle
  - แนวโน้ม peak memory เพื่อดูโอกาส memory leak
- **หมายเหตุ**: Churn ไม่ได้เน้นส่ง chat ต่อเนื่อง ดังนั้น msg/s ไม่ใช่ตัวชี้วัดหลัก

#### 4) Saturation
- **รูปแบบโหลด**: 200 → 500 → 1000 VUs, แต่ละ VU ส่ง 5 ข้อความ/วินาที
- **วัตถุประสงค์**: หาเพดาน throughput เมื่อระบบถูกกดโหลดหนักต่อเนื่อง
- **ค่าที่ควรโฟกัส**:
  - Throughput สูงสุดที่ระบบยังรับไหว
  - p95 connect latency (`ws_connecting`/`ws_connect_duration`)
  - Peak memory ที่ระดับ concurrency สูง

### วิธีอ่านผลแบบเร็ว

1. เริ่มจาก **Steady** ก่อน (ภาพรวมการใช้งานปกติ)
2. ใช้ **Burst** และ **Saturation** เทียบความสามารถรองรับโหลดหนัก
3. ใช้ **Churn** ดูความแข็งแรงของ connection lifecycle (ไม่เน้น msg/s)
4. อ่าน `ws_errors` ตามบริบทของ scenario (จังหวะเริ่ม/จบรัน vs ความผิดพลาดระหว่างรันจริง)

### แผนถัดไป: Long-run Benchmark (120 วินาที ถึง 5 นาที)

> สถานะ: วางแผนไว้แล้ว เดี๋ยวทำต่อในรอบถัดไป

เพื่อให้ตอบโจทย์การทดสอบแบบ "อยู่ยาว" จะเพิ่มโหมด benchmark ระยะยาวดังนี้:

- `quick` (โหมดปัจจุบัน): ใช้รอบสั้นสำหรับเทียบผลเร็ว
- `soak120`: ทดสอบ 120 วินาที
- `soak300`: ทดสอบ 300 วินาที (5 นาที)

KPI ที่จะเพิ่มในการสรุปผลรอบยาว:
- ความเสถียรของ `ws_errors` ตลอดช่วงรัน
- แนวโน้มหน่วยความจำ (peak และพฤติกรรมช่วงท้ายรัน)
- Throughput ช่วงท้ายเทียบกับช่วงต้น (ดูการตกของประสิทธิภาพ)
- Drop rate ภายใต้โหลดต่อเนื่อง

เกณฑ์ผ่านเบื้องต้น (Draft):
- รันครบเวลาโดยไม่ crash
- `ws_errors` ไม่พุ่งต่อเนื่องผิดปกติ
- ไม่พบอาการ memory โตต่อเนื่องแบบผิดปกติ
- Throughput ช่วงท้ายไม่ตกฮวบเมื่อเทียบช่วงต้น

## ผลลัพธ์ (Profile B — Docker, arm64, 2026-02-27)

### Steady Load — 100 VUs × 1 msg/s × 60 วินาที

| ภาษา | Throughput (msg/s) | Messages | Connections | Drop rate | k6 errors |
|------|--------------------|----------|-------------|-----------|-----------|
| Go       | 84.49              | 5,915    | 100         | 0.00%     | 125       |
| Rust     | **85.35**          | 5,975    | 100         | 0.00%     | 0         |
| Zig      | 83.30              | 5,915    | 100         | 0.00%     | 0         |

### Burst — ramp 0→1,000 VUs ใน 10 วินาที, ค้าง 5 วินาที, ลดลง 5 วินาที

| ภาษา | Throughput (msg/s) | Messages | Peak conns | k6 errors |
|------|--------------------|----------|------------|-----------|
| Go       | 44.42              | 1,333    | 1,333      | 333       |
| Rust     | **44.43**          | 1,333    | 1,333      | 333       |
| Zig      | 43.47              | 1,333    | 1,333      | 333       |

> burst error จำนวน 333 เกิดจากการที่บาง connection พยายาม join ช่วง ramp-down ตอนที่เวลา duration ของเซิร์ฟเวอร์ใกล้หมดแล้ว ไม่ใช่บั๊กหลักของเซิร์ฟเวอร์

### Churn — 200 VUs × connect→join→2s→leave, 60 วินาที

| ภาษา | Total connections | Connection rate | k6 errors |
|------|-------------------|-----------------|-----------|
| Go       | 6,000             | ~100 conn/s     | 0         |
| Rust     | 6,000             | ~100 conn/s     | 0         |
| Zig      | 6,000             | ~100 conn/s     | 0         |

> Churn ไม่ได้เน้นส่งข้อความ chat ต่อเนื่อง ตัวชี้วัดหลักคือ **total connections** (ความสามารถของ connection lifecycle) ไม่ใช่ msg/s โดยผลรอบนี้ทั้ง 3 ภาษาไม่มี error

### ขนาดไบนารี

| ภาษา | Binary |
|------|--------|
| Go       | 5.43 MB |
| Rust     | **1.50 MB** |
| Zig      | 2.43 MB |

## สรุปประเด็นสำคัญ

1. **Throughput ใกล้เคียงกันมาก** ทั้ง 3 ภาษา (~83–85 msg/s ใน steady, ~44 msg/s ใน burst) แปลว่าคอขวดอยู่ที่พารามิเตอร์โหลดของ k6 มากกว่าตัว implementation ของเซิร์ฟเวอร์

2. **Rust มีขนาดไบนารีเล็กที่สุด** (1.50 MB) ขณะที่ Zig (2.43 MB) ยังเล็กกว่า Go (5.43 MB)

3. **กลไก broadcast ของ Zig (facil.io pub/sub)** ใช้แนว channel subscription ซึ่งต่างจาก Go/Rust แต่ throughput ที่ได้ยังอยู่ในระดับใกล้เคียงกัน

4. ใน steady load ของ Profile B, **Go มี ws_errors 125** ขณะที่ Rust/Zig เป็น 0 โดยพฤติกรรมนี้สัมพันธ์กับวิธี close handshake ที่ต่างกัน ไม่ได้ชี้ว่าระบบใช้งานจริงผิดฟังก์ชันทันที แต่เป็นความต่างเชิง implementation

5. **Churn stress test** (connect/disconnect 6,000 รอบใน 60 วินาที) ผ่านโดยไม่มี error ในทั้ง 3 ภาษา สะท้อนว่า lifecycle การเชื่อมต่อและ cleanup ทำงานได้ถูกต้อง

6. **Rate limiter ถูกต้องตามสเปก**: ทั้ง 3 ภาษาใช้ token bucket (10 tokens/s) และ drop ข้อความส่วนเกินโดยไม่ตัดการเชื่อมต่อ

## ผลลัพธ์ (Profile A — Docker, arm64, 2026-02-28)

### Steady Load — 100 VUs × 1 msg/s × 60 วินาที

| ภาษา | เฟรมเวิร์ก | Throughput (msg/s) | Messages | Connections | Drop rate | k6 errors |
|------|-----------|--------------------|----------|-------------|-----------|-----------|
| Go       | GoFiber   | 84.39              | 5,908    | 100         | 0.00%     | 114       |
| Rust     | Axum      | **85.22**          | 5,966    | 100         | 0.00%     | 0         |
| Zig      | zap       | 83.26              | 5,903    | 100         | 0.00%     | 0         |

### Burst — ramp 0→1,000 VUs ใน 10 วินาที, ค้าง 5 วินาที, ลดลง 5 วินาที

| ภาษา | เฟรมเวิร์ก | Throughput (msg/s) | Messages | Peak conns | k6 errors |
|------|-----------|--------------------|----------|------------|-----------|
| Go       | GoFiber   | 44.46              | 1,334    | 1,334      | 334       |
| Rust     | Axum      | **44.43**          | 1,333    | 1,333      | 333       |
| Zig      | zap       | 42.98              | 1,333    | 1,333      | 331       |

### Churn — 200 VUs × connect→join→2s→leave, 60 วินาที

| ภาษา | เฟรมเวิร์ก | Total connections | k6 errors |
|------|-----------|-------------------|-----------|
| Go       | GoFiber   | 6,765             | 765       |
| Rust     | Axum      | 6,000             | 0         |
| Zig      | zap       | 6,000             | 0         |

### Saturation — 200→500→1000 VUs × 5 msg/s

| ภาษา | เฟรมเวิร์ก | Throughput (msg/s) | Messages | Connections | Drop rate | k6 errors |
|------|-----------|--------------------|----------|-------------|-----------|-----------|
| Go       | GoFiber   | 2,579.20           | 296,613  | 1,123       | 0.00%     | 36,080    |
| Rust     | Axum      | 560.44             | 64,464   | 1,000       | 1.36%     | 9,010     |
| Zig      | zap       | **2,929.32**       | 338,456  | 1,000       | 0.00%     | 805       |

### ขนาดไบนารี

| ภาษา | โปรไฟล์ B | โปรไฟล์ A | ความต่าง |
|------|-----------|-----------|---------|
| Go       | 5.43 MB   | 6.18 MB   | +14%  |
| Rust     | **1.50 MB** | 1.94 MB | +29%  |
| Zig      | 2.43 MB   | 2.43 MB   | 0%    |

---

## เปรียบเทียบ Profile A vs Profile B

| ภาษา | โปรไฟล์ | เฟรมเวิร์ก | Steady (msg/s) | Burst (msg/s) | Saturation (msg/s) |
|------|---------|-----------|----------------|---------------|--------------------|
| Go       | B       | net/http + gorilla | 84.49 | 44.42 | N/A |
| Go       | A       | GoFiber v2         | 84.39 | 44.46 | 2,579.20 |
| Rust     | B       | tokio-tungstenite  | 85.35 | 44.43 | N/A |
| Rust     | A       | Axum 0.7           | 85.22 | 44.43 | 560.44 |
| Zig      | B       | zap (facil.io)     | 83.30 | 43.47 | N/A |
| Zig      | A       | zap (same)         | 83.26 | 42.98 | 2,929.32 |

### สรุปประเด็นสำคัญ (Profile A vs B)

1. **ผลกระทบจาก framework ต่อ throughput ค่อนข้างน้อย** ทั้ง 6 คอนฟิกให้ตัวเลข steady/burst ใกล้กันมาก

2. **GoFiber ยังมี churn anomaly** (6,765 connections เทียบกับคาดหมาย 6,000 และ ws_errors 765) ซึ่งเกี่ยวกับพฤติกรรมตอน upgrade connection ของ fasthttp ที่ต่างจาก `net/http`

3. **Saturation แยกความต่างได้ชัดเจน**: Zig (2,929.32 msg/s) และ Go (2,579.20 msg/s) สูงกว่า Rust (560.44 msg/s) มาก พร้อมกับ Rust มี drop rate 1.36%

4. **ขนาดไบนารีเพิ่มขึ้นเมื่อเพิ่ม framework dependency**: Go +14%, Rust +29%, ส่วน Zig ไม่เปลี่ยนเพราะใช้โค้ดชุดเดิม

5. **Rust ยังเป็นไบนารีที่เล็กที่สุด** ทั้งสองโปรไฟล์ (1.50 MB → 1.94 MB)

---

## Dependencies หลัก

| ภาษา | ไลบรารีหลัก |
|------|---------------|
| Go       | `gorilla/websocket v1.5.3` |
| Rust     | `tokio 1`, `tokio-tungstenite 0.26`, `clap 4`, `serde_json` |
| Zig      | `zap v0.11.0` (wraps facil.io 0.7.4) |
