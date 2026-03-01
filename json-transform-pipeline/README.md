# JSON Transform Pipeline

เปรียบเทียบ performance ของ Go, Rust, และ Zig ในการอ่าน JSONL file ขนาดใหญ่, parse แต่ละ record, extract field, และ accumulate aggregate — เป็น benchmark สำหรับ JSON deserialization throughput และ memory allocation pattern

## โครงสร้างโปรเจกต์

```
json-transform-pipeline/
├── go/
│   ├── main.go          # encoding/json + bufio.Scanner
│   ├── go.mod
│   └── Dockerfile
├── rust/
│   ├── src/main.rs      # serde_json + BufReader lines()
│   ├── Cargo.toml
│   └── Dockerfile
├── zig/
│   ├── src/main.zig     # std.json.parseFromSlice + splitScalar
│   ├── build.zig
│   ├── build.zig.zon
│   └── Dockerfile
├── test-data/           # .gitignore — generate locally
│   └── records.jsonl    # 100,000 lines ~6.5MB
└── benchmark/
    ├── run.sh
    └── results/
```

## สร้าง Test Data

```bash
python3 -c "
import json, random
random.seed(42)
with open('test-data/records.jsonl', 'w') as f:
    for i in range(100000):
        obj = {'id': i, 'name': f'user_{i}', 'score': round(random.random()*100, 2), 'active': i%2==0}
        f.write(json.dumps(obj) + '\n')
"
```

## Dependencies

| ภาษา | Library | หมายเหตุ |
|------|---------|---------|
| Go | stdlib `encoding/json` | allocates per field |
| Rust | `serde_json = "1"` + `serde` | zero-copy + compile-time codegen |
| Zig | stdlib `std.json` | DOM parser per line |

## Build & Run

```bash
# Local build
unset GOROOT && go build -o ../bin/jtp-go .
cargo build --release
zig build -Doptimize=ReleaseFast

# Docker
docker build -t jtp-go go/
docker run --rm -v "$(pwd)/test-data":/data jtp-go /data/records.jsonl

# Benchmark
bash benchmark/run.sh
```

## ผลการทดสอบ (Docker ARM64, Apple M2)

> **Test**: 100,000 JSONL lines (~6.5MB) — 5 runs (1 warm-up + 4 measured)
> **Results saved to**: `benchmark/results/json-transform-pipeline_20260301_150329.txt`

```
── Throughput (lines/sec, higher is better) ──────────────
  Go  : 1,125,518 lines/sec  avg  (Min: 1,087,683 | Max: 1,147,918)
  Rust: 5,393,905 lines/sec  avg  (Min: 5,179,659 | Max: 5,474,178)  ✓ Winner
  Zig :   144,509 lines/sec  avg  (Min: 141,610   | Max: 147,996)
```

### เปรียบเทียบ

| | Go | Rust | Zig |
|---|---|---|---|
| Throughput | 1.13M lines/s | **5.39M lines/s** | 144K lines/s |
| Processing time (100K lines) | ~0.089s | ~0.019s | ~0.685s |
| Relative | 1× | **4.8×** | 0.13× |
| Approach | `encoding/json` Unmarshal | `serde_json` + `#[derive]` | `std.json.parseFromSlice` |
| Allocation | per-field | compile-time schema | per-line DOM |

```
── Binary Sizes ──────────────────────────────────────────
  Go  : 3.4MB
  Rust: 2.1MB
  Zig : 1.7MB
```

**Key insight:** **Rust ชนะขาด 4.8× เหนือ Go และ 37× เหนือ Zig** เพราะ `serde_json` + `#[derive(Deserialize)]` สร้าง type-specific parser ตอน compile time — ไม่มี reflection, ไม่มี dynamic dispatch

- **Rust ชนะเพราะ compile-time code generation**: `#[derive(Deserialize)]` สร้าง parser ที่รู้ struct layout ล่วงหน้า — LLVM optimize ได้เต็มที่; `serde_json` ยังใช้ zero-copy string references สำหรับ field ที่ไม่ต้อง own
- **Go ช้ากว่า Rust 4.8× เพราะ**: `encoding/json` ใช้ reflection ตอน runtime สแกน struct tags, allocate `interface{}` intermediate, และ copy string ทุก field — ทำงานถูกต้องแต่ไม่ optimal
- **Zig ช้าที่สุดเพราะ**: `std.json.parseFromSlice` สร้าง full DOM tree per line + `defer parsed.deinit()` ใน loop มี allocation/deallocation overhead สูงมาก; `std.json` ยังไม่ mature เหมือน serde_json
- **บทเรียน**: สำหรับ JSON parsing throughput, framework ที่ใช้ compile-time code generation ชนะ runtime reflection อย่างมีนัยสำคัญ — Rust's serde เป็น best-in-class; ถ้าต้องการ Go ที่เร็วขึ้น ควรใช้ `gjson` หรือ manual parsing แทน `encoding/json`

## หมายเหตุ

- **Go**: `encoding/json.Unmarshal` เป็น standard approach — ง่าย, safe, แต่ใช้ reflection
- **Rust**: `serde` + `serde_json` เป็น de facto standard Rust JSON library — zero overhead abstractions
- **Zig**: `std.json` ยังอยู่ในช่วง active development — DOM parsing API ปัจจุบันมี allocation overhead สูง; streaming/zero-copy API กำลัง develop
- **Test data**: repetitive structure (100K records สร้าง pattern เดิม) เหมาะสำหรับ CPU branch prediction
