# Compare Rust / Go / Zig

29 mini-projects เปรียบเทียบ **Go**, **Rust**, และ **Zig** แบบวัดผลได้จริงด้วย Docker benchmark
รวมถึง **WebSocket Public Chat** — โปรเจกต์พิเศษที่ทดสอบ production stability ด้วย soak benchmark 300s+180s

เป้าหมาย: หาว่าแต่ละภาษา **เก่งเรื่องอะไร ด้อยเรื่องอะไร** ในงานจริง ไม่ใช่แค่ microbenchmark สังเคราะห์

---

## 🏆 ผลรวม (29 โปรเจกต์)

| ภาษา | ชนะ | สัดส่วน |
|------|----:|--------:|
| **Zig** | **16** | **55%** |
| **Rust** | 8 | 28% |
| **Go** | 5 | 17% |

ดูตารางผลลัพธ์ทั้งหมด → **[SUMMARY.md](./SUMMARY.md)** | ตัวเลข raw → **[PLAN.md](./PLAN.md)**

---

## ❓ ทำไมแต่ละภาษาถึงชนะ/แพ้

### Zig ชนะมากสุด (56%)
ไม่มี GC, ไม่มี async runtime → CPU cycles ทุกอันไปที่งานจริง
- **data loop ซ้ำมาก**: SQLite 897M items/s (3.2× เหนือ Rust), CSV Aggregator 23M items/s
- **latency ต่ำสุด**: Audio Chunker 17 ns (Go ช้ากว่า 250×!)
- **ไม่ต้อง clone()**: KV Store ไม่ต้องสร้าง String ใหม่ทุก operation → 3× เหนือ Rust

**จุดอ่อน**: naive broadcast loop เป็น O(n) sequential blocking — WebSocket fan-out ได้ 578 msg/s เมื่อใช้ pure Zig (vs 2,945 เมื่อใช้ facil.io C library)

### Rust ชนะงาน async + regex + production stability
LLVM SIMD + Tokio async I/O
- **regex/string search ยาว**: Log Masker 41.7 MB/s (10× เหนือ Go) ด้วย SIMD DFA engine
- **async TCP**: Port Scanner 108K items/s async (Go sync: 664 items/s)
- **binary เล็กสุด**: ~388KB ทุกโปรเจกต์
- **WebSocket soak 480s**: 0 ws_errors, memory 6 MiB คงที่, throughput 95 msg/s — production-ready

### Go ชนะงาน HTTP networking
stdlib HTTP + connection pooling
- **Reverse Proxy**: 10,065 r/s (2.8× เหนือ Rust) ด้วย `httputil.ReverseProxy` pool
- **PNG encoding**: 58.1M items/s ด้วย `image/png` stdlib ที่ optimize ดีมาก
- **DNS cache**: `net.Dial` cache DNS result → ชนะใน repeated TCP connection workloads

---

## 📁 โครงสร้าง Repository

```text
compare-rust-go-zig/
├── <project-name>/         # 29 mini-projects (groups 1–10)
│   ├── go/                 main.go + Dockerfile
│   ├── rust/               src/main.rs + Cargo.toml + Dockerfile
│   ├── zig/                src/main.zig + build.zig + Dockerfile
│   ├── test-data/          gitignored input data
│   ├── benchmark/
│   │   ├── run.sh          Docker-based benchmark script
│   │   └── results/        raw output files (timestamp)
│   └── README.md           setup + results + key insight
├── websocket-public-chat/  # โปรเจกต์พิเศษ — WebSocket server (2 profiles × 2 modes)
├── PLAN.md                 ตารางผลทุกโปรเจกต์ + winner
├── SUMMARY.md              วิเคราะห์ patterns + คำแนะนำ + WebSocket soak results
└── README.md               (ไฟล์นี้)
```

---

## 🗂 10 กลุ่มโปรเจกต์

| กลุ่ม | Theme | ผู้ชนะ |
|-------|-------|-------|
| 1 | Video & Media Processing | Go (1.1), Zig (1.2, 1.3) |
| 2 | Infrastructure & Networking | Go (2.1), Zig (2.2), Rust (2.3) |
| 3 | AI & Data Pipeline | Go (3.1), Zig (3.2), Rust (3.3) |
| 4 | DevOps Tools | Zig (4.1, 4.2), Rust (4.3) |
| 5 | Systems Fundamentals | Zig (5.1, 5.2, 5.3) |
| 6 | Integration & Data | Zig (6.1, 6.3), Rust (6.2) |
| 7 | Low-Level Networking | Rust (7.1, 7.2), Zig (7.3) |
| 8 | Image Processing (Zero-dependency) | Go (8.1, 8.2), Zig (8.3) |
| 9 | Data Engineering Primitives | Zig (9.1, 9.2), Rust (9.3) |
| 10 | Serialization & Encoding | Rust (10.1), Zig (10.2) |

---

## 🎓 Learning Path — เริ่มอ่านที่ไหนดี?

เลือก track ที่ตรงกับคำถามที่อยากตอบ แต่ละ track ใช้เวลา ~1 ชั่วโมงอ่าน README + ดูโค้ด:

### Track A — "ทำไม Rust ถึงชนะงาน async?"

| โปรเจกต์ | แนวคิดที่เรียน |
|---------|--------------|
| [`tcp-port-scanner`](./tcp-port-scanner/README.md) | async vs sync: ต่าง 163× (108K vs 664 items/s) เพราะ `tokio` ไม่บล็อก thread ขณะรอ TCP connection |
| [`local-asr-llm-proxy`](./local-asr-llm-proxy/README.md) | I/O-wait-dominated: Go goroutine pool ชนะเมื่อ backend latency 10-50ms เพราะ connection reuse |
| [`custom-log-masker`](./custom-log-masker/README.md) | LLVM SIMD auto-vectorize regex บน strings ยาว >64 bytes: 10× เหนือ Go |
| [`websocket-public-chat`](./websocket-public-chat/README.md) | broadcast fan-out: Rust `try_send` non-blocking ชนะ pure Zig sequential mutex loop |

### Track B — "ทำไม Zig ถึงชนะงาน data loop?"

| โปรเจกต์ | แนวคิดที่เรียน |
|---------|--------------|
| [`in-memory-kv-store`](./in-memory-kv-store/README.md) | zero-alloc get path: ไม่ต้อง `.clone()` String → 3× เหนือ Rust |
| [`sqlite-query-engine`](./sqlite-query-engine/README.md) | comptime inlining + no GC pause: B-tree scan 897M items/s (2.5× เหนือ Rust) |
| [`csv-stream-aggregator`](./csv-stream-aggregator/README.md) | streaming parse ไม่ allocate buffer ต่อ row: 23M items/s vs Rust 8M |
| [`tiny-health-check-agent`](./tiny-health-check-agent/README.md) | tight inner loop ไม่มี runtime overhead: 657M checks/s |

### Track C — "เมื่อไหร่ Go ถึงชนะ?"

| โปรเจกต์ | แนวคิดที่เรียน |
|---------|--------------|
| [`high-perf-reverse-proxy`](./high-perf-reverse-proxy/README.md) | `httputil.ReverseProxy` + HTTP/1.1 connection pool: 2.8× เหนือ Rust |
| [`png-encoder-from-scratch`](./png-encoder-from-scratch/README.md) | `image/png` stdlib ที่ optimize อย่างดี: 58M items/s vs Zig 27M |
| [`local-asr-llm-proxy`](./local-asr-llm-proxy/README.md) | goroutine pool ชนะเมื่อ workload เป็น I/O-wait-dominated — อ่านคู่กับ Track A |

### Track D — "Serialization & Encoding: zero-copy vs FFI"

| โปรเจกต์ | แนวคิดที่เรียน |
|---------|--------------|
| [`json-transform-pipeline`](./json-transform-pipeline/README.md) | Rust `serde_json` compile-time codegen ชนะ Go reflection 4.8× และ Zig DOM parser 37× |
| [`zstd-compression`](./zstd-compression/README.md) | Zig direct `@cImport` ชนะ Rust safe FFI wrapper 1.7× บน C library — ยืนยัน subtitle-burn-in finding |

> **หมายเหตุ**: ผลต่าง < 10% ถือว่า "เท่ากันในทางปฏิบัติ" เฉพาะ 2× ขึ้นไปถือเป็น structural advantage ดู [SUMMARY.md § วิธีอ่านตาราง](./SUMMARY.md) สำหรับรายละเอียด

---

## 🔌 WebSocket Public Chat (โปรเจกต์พิเศษ)

เทียบ WebSocket chat server ด้วย 2 profiles (framework / stdlib) และ 2 benchmark modes:

| Mode | Scenarios | Duration | วัด |
|------|-----------|----------|-----|
| **quick** | Steady / Burst / Churn / Saturation | ~4 นาที | throughput, memory, CPU, errors |
| **soak** | Steady-soak / Churn-soak | ~25 นาที | memory drift, ws_errors/s, stability |

### Soak Results — Profile A (2026-02-28)

| ภาษา | Steady-soak 300s | Peak mem | ws_err/s | Churn-soak 180s |
|------|-----------------|----------|---------|----------------|
| Go (GoFiber) | 93.88 msg/s | 15 MiB | 2.54 ⚠️ | 21,251 conns ⚠️ |
| **Rust (Axum)** | **95.14 msg/s** | **6 MiB** | **0.00** | **18,000 conns** |
| Zig (zap) | 94.70 msg/s | 30 MiB | **0.00** | 18,000 conns |

**ข้อสรุป**: ทุกภาษา **ไม่มี memory leak** — Rust และ Zig error-free ตลอด 480s

```bash
cd websocket-public-chat
bash benchmark/run-soak-profile-a.sh   # ~25 นาที
```

---

## 🚀 วิธีรัน Benchmark

```bash
# รัน benchmark โปรเจกต์ใดโปรเจกต์หนึ่ง
cd <project-name>
bash benchmark/run.sh

# ผลบันทึกอัตโนมัติใน:
# <project-name>/benchmark/results/<project>_<timestamp>.txt
```

**ข้อกำหนด**: Docker daemon ต้องรันอยู่ (`docker info`)

---

## 📊 รูปแบบ Statistics มาตรฐาน

ทุกภาษาในโปรเจกต์เดียวกันรายงานรูปแบบเดียวกัน:

```
--- Statistics ---
Total processed: <N>
Processing time: <X.XXX>s
Average latency: <X.XXX>ms
Throughput: <X.XX> items/sec
```

---

## ⚙️ Build Local (ทดสอบก่อน benchmark)

```bash
# Go (ต้อง unset GOROOT ก่อนทุกครั้ง)
unset GOROOT && go build -o ../bin/<name>-go .

# Rust
cargo build --release

# Zig
zig build -Doptimize=ReleaseFast
```

---

## 📖 อ่านต่อ

- **[PLAN.md](./PLAN.md)** — ตารางตัวเลขดิบทุกโปรเจกต์ พร้อมผู้ชนะแต่ละแถว
- **[SUMMARY.md](./SUMMARY.md)** — วิเคราะห์ว่า "ทำไม" แต่ละภาษาถึงชนะ + WebSocket soak analysis + คำแนะนำเลือกภาษา
- **`<project>/README.md`** — รายละเอียด setup, ผล benchmark, และ key insight ของแต่ละโปรเจกต์
- **[websocket-public-chat/README.md](./websocket-public-chat/README.md)** — WebSocket deep-dive: quick + soak results, improvement history
