# Compare Rust / Go / Zig

27 mini-projects เปรียบเทียบ **Go**, **Rust**, และ **Zig** แบบวัดผลได้จริงด้วย Docker benchmark

เป้าหมาย: หาว่าแต่ละภาษา **เก่งเรื่องอะไร ด้อยเรื่องอะไร** ในงานจริง ไม่ใช่แค่ microbenchmark สังเคราะห์

---

## 🏆 ผลรวม (27 โปรเจกต์)

| ภาษา | ชนะ | สัดส่วน |
|------|----:|--------:|
| **Zig** | **15** | **56%** |
| **Rust** | 7 | 26% |
| **Go** | 5 | 19% |

ดูตารางผลลัพธ์ทั้งหมด → **[SUMMARY.md](./SUMMARY.md)** | ตัวเลข raw → **[PLAN.md](./PLAN.md)**

---

## ❓ ทำไมแต่ละภาษาถึงชนะ/แพ้

### Zig ชนะมากสุด (56%)
ไม่มี GC, ไม่มี async runtime → CPU cycles ทุกอันไปที่งานจริง
- **data loop ซ้ำมาก**: SQLite 897M items/s (3.2× เหนือ Rust), CSV Aggregator 23M items/s
- **latency ต่ำสุด**: Audio Chunker 17 ns (Go ช้ากว่า 250×!)
- **ไม่ต้อง clone()**: KV Store ไม่ต้องสร้าง String ใหม่ทุก operation → 3× เหนือ Rust

### Rust ชนะงาน async + regex + production stability
LLVM SIMD + Tokio async I/O
- **regex/string search ยาว**: Log Masker 41.7 MB/s (10× เหนือ Go) ด้วย SIMD DFA engine
- **async TCP**: Port Scanner 108K items/s async (Go sync: 664 items/s)
- **binary เล็กสุด**: ~388KB ทุกโปรเจกต์
- **WebSocket soak (300s+180s)**: 0 ws_errors, memory คงที่, throughput 95 msg/s ตลอด 5 นาที

### Go ชนะงาน HTTP networking
stdlib HTTP + connection pooling
- **Reverse Proxy**: 10,065 r/s (2.8× เหนือ Rust) ด้วย `httputil.ReverseProxy` pool
- **PNG encoding**: 58.1M items/s ด้วย `image/png` stdlib ที่ optimize ดีมาก
- **DNS cache**: `net.Dial` cache DNS result → ชนะใน repeated TCP connection workloads

---

## 📁 โครงสร้าง Repository

```text
compare-rust-go-zig/
├── <project-name>/
│   ├── go/           main.go + Dockerfile
│   ├── rust/         src/main.rs + Cargo.toml + Dockerfile
│   ├── zig/          src/main.zig + build.zig + Dockerfile
│   ├── test-data/    gitignored input data
│   ├── benchmark/
│   │   ├── run.sh    Docker-based benchmark script
│   │   └── results/  raw output files (timestamp)
│   └── README.md     setup + results + key insight
├── PLAN.md           ตารางผลทุกโปรเจกต์ + winner
├── SUMMARY.md        วิเคราะห์ patterns + คำแนะนำ
└── README.md         (ไฟล์นี้)
```

---

## 🗂 9 กลุ่มโปรเจกต์

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
- **[SUMMARY.md](./SUMMARY.md)** — วิเคราะห์ว่า "ทำไม" แต่ละภาษาถึงชนะ + คำแนะนำเลือกภาษา
- **`<project>/README.md`** — รายละเอียด setup, ผล benchmark, และ key insight ของแต่ละโปรเจกต์
