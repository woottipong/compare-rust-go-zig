# Compare Rust / Go / Zig

Repository นี้ใช้ mini projects จริงเพื่อเปรียบเทียบ **Go**, **Rust**, และ **Zig** ในหลายโดเมน เช่น media, networking, systems, data engineering และ integration workloads

เป้าหมายหลัก:
- เปรียบเทียบ **performance** แบบวัดผลได้จริง
- เปรียบเทียบ **binary size / memory behavior / code complexity**
- สร้าง baseline ที่ทำซ้ำได้ด้วย **Docker benchmark**

---

## สถานะปัจจุบัน

- ✅ Completed: **27/27 projects**
- ✅ ครบทั้ง **9 groups**
- ✅ ทุกโปรเจกต์มี **Go + Rust + Zig** implementation
- ✅ มี benchmark script และผลลัพธ์ใน `benchmark/results/`

ดูรายละเอียดทั้งหมดใน [`plan.md`](./plan.md)

### ดูผล benchmark ได้ที่ไหน

1. **ไฟล์ผลรันจริง (raw output):**
   - `<project-name>/benchmark/results/<project>_<timestamp>.txt`
2. **สรุปผลรายโปรเจกต์:**
   - `<project-name>/README.md`
3. **ภาพรวมทั้ง repository:**
   - [`plan.md`](./plan.md)

---

## Repository Structure

```text
compare-rust-go-zig/
├── <project-name>/
│   ├── go/
│   ├── rust/
│   ├── zig/
│   ├── test-data/
│   ├── benchmark/
│   │   ├── run.sh
│   │   └── results/
│   └── README.md
├── plan.md
└── .windsurf/rules/
    ├── project-rules.md
    ├── project-structure.md
    ├── go-dev.md
    ├── rust-dev.md
    └── zig-dev.md
```

---

## Project Groups

| Group | Theme | Status |
|---|---|---|
| 1 | Video & Media Processing | ✅ 3/3 |
| 2 | Infrastructure & Networking | ✅ 3/3 |
| 3 | AI & Data Pipeline | ✅ 3/3 |
| 4 | DevOps Tools | ✅ 3/3 |
| 5 | Systems Fundamentals | ✅ 3/3 |
| 6 | Integration & Data | ✅ 3/3 |
| 7 | Low-Level Networking | ✅ 3/3 |
| 8 | Image Processing (Zero-dependency) | ✅ 3/3 |
| 9 | Data Engineering Primitives | ✅ 3/3 |

---

## วิธีรัน Benchmark (มาตรฐาน)

แต่ละโปรเจกต์ใช้ benchmark ของตัวเอง:

```bash
cd <project-name>
bash benchmark/run.sh
```

ผลลัพธ์จะถูกบันทึกอัตโนมัติใน:

```text
<project-name>/benchmark/results/<project>_<timestamp>.txt
```

แนวทางการวัดผล:
- Non-HTTP workloads: 5 runs (1 warm-up + 4 measured)
- HTTP workloads: ใช้ `wrk` และ Docker network
- Zig output ต้อง capture `2>&1`

---

## Statistics Format (มาตรฐานร่วม)

ทุกภาษาในโปรเจกต์เดียวกันต้องรายงานรูปแบบเดียวกัน:

```text
--- Statistics ---
Total processed: <N>
Processing time: <X.XXX>s
Average latency: <X.XXX>ms
Throughput: <X.XX> items/sec
```

> ชื่อ field อาจปรับตาม domain (เช่น requests/chunks/lines) แต่โครงสร้างต้องเท่ากัน

---

## Quick Start

### Prerequisites

```bash
# macOS
brew install docker ffmpeg zig go rust

# Ubuntu/Debian (ตัวอย่าง)
sudo apt-get update
sudo apt-get install -y docker.io ffmpeg curl build-essential
```

### Local Build (ภายในแต่ละภาษา)

```bash
# Go
unset GOROOT && go build -o ../bin/<name>-go .

# Rust
cargo build --release

# Zig
zig build -Doptimize=ReleaseFast
```

---

## Rules & Standards

ยึดตามไฟล์ใน `.windsurf/rules/` เป็นหลัก โดยเฉพาะ:

1. [`project-rules.md`](./.windsurf/rules/project-rules.md)
2. [`project-structure.md`](./.windsurf/rules/project-structure.md)

สาระสำคัญ:
- Benchmark ต้องผ่าน Docker
- `main()` เน้น orchestration เท่านั้น
- มี Stats struct แยกชัดเจน
- Docker image naming: `<prefix>-go`, `<prefix>-rust`, `<prefix>-zig`

---

## สรุปภาพรวมเชิงเทคนิค

- **Go** เด่นในงาน network/runtime ที่ใช้ stdlib ได้ตรงจุด
- **Rust** เด่นในงาน async throughput สูง และ parser/regex
- **Zig** เด่นในงาน data/system ที่ได้ประโยชน์จาก low-overhead + manual memory

รายละเอียดเชิงลึกของแต่ละโจทย์ ให้ดู `README.md` ในโฟลเดอร์โปรเจกต์นั้นๆ
