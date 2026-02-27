# In-Memory Key-Value Store: Go vs Rust vs Zig

วัด throughput ของ GET/SET/DELETE operations บน in-memory HashMap ด้วย mutex protection เพื่อเทียบ hash map implementation และ string handling ระหว่าง 3 ภาษา

## โครงสร้าง

```text
in-memory-kv-store/
├── go/
│   ├── main.go         # sync.RWMutex + map[string]string
│   ├── go.mod
│   └── Dockerfile
├── rust/
│   ├── src/main.rs     # RwLock<HashMap<String,String>>
│   ├── Cargo.toml
│   └── Dockerfile
├── zig/
│   ├── src/main.zig    # std.Thread.Mutex + StringHashMap
│   ├── build.zig
│   └── Dockerfile
├── benchmark/
│   ├── results/
│   └── run.sh
└── README.md
```

## Dependencies

- Docker (for benchmark)

## Build

```bash
# Go
unset GOROOT && go build -o ../bin/ikvs-go ./go

# Rust
cargo build --release --manifest-path rust/Cargo.toml

# Zig
cd zig && zig build -Doptimize=ReleaseFast
```

## Run Benchmark

```bash
bash benchmark/run.sh
# Results saved to benchmark/results/
```

## Benchmark Results

อ้างอิงจาก: `benchmark/results/in-memory-kv-store_20260227_125840.txt`

```
Operations: 3,000,000 per run
Total ops : 7,500,000 (3M SET + 3M GET + 1.5M DELETE)
Mode      : Docker
```

| Run | Go | Rust | Zig |
|-----|---:|-----:|----:|
| Warm-up | 1412ms | 2745ms | 1091ms |
| Run 2 | 1294ms | 2370ms | 738ms |
| Run 3 | 1429ms | 2308ms | 1123ms |
| Run 4 | 1305ms | 2665ms | 886ms |
| Run 5 | 1563ms | 2328ms | 1140ms |
| **Avg** | **1397ms** | **2417ms** | **971ms** |
| Min | 1294ms | 2308ms | 738ms |
| Max | 1563ms | 2665ms | 1140ms |

### Summary

| Metric | Go | Rust | Zig |
|--------|---:|-----:|----:|
| Avg Time | 1,397ms | 2,417ms | **971ms** |
| Throughput | 4.8M ops/s | 3.2M ops/s | **6.6M ops/s** |
| Binary Size | 1.5MB | **388KB** | 2.2MB |
| Code Lines | 181 | **126** | 164 |

## Key Insight

**Zig ชนะ 1.4× เหนือ Go และ 2.5× เหนือ Rust — เพราะ string handling ใน get()**

ความแตกต่างหลักไม่ใช่ hash map algorithm แต่เป็น **string return semantics ใน get()**:

| ภาษา | get() returns | Heap alloc per call? |
|------|--------------|---------------------|
| **Zig** | `?[]const u8` (slice into map) | **ไม่มี** |
| **Go** | `string` (header copy, shared backing array) | **ไม่มี** |
| **Rust** | `Option<String>` via `.cloned()` | **ทุก call** |

- **Rust ช้าที่สุด**: `get()` ใช้ `.cloned()` ทำ heap allocation ใหม่สำหรับทุก GET → 3M heap allocs ใน GET phase + deallocate ทุก call → memory pressure สูง
- **Go ตรงกลาง**: `map[string]string` คืน string header (pointer+len) ไม่ deep copy → GC ยังต้องตามเก็บ references
- **Zig เร็วสุด**: `StringHashMap` คืน slice (pointer+len) ชี้เข้า map โดยตรง → zero allocation ใน get path

**Rust binary เล็กสุด 388KB** (ไม่มี GC runtime, ไม่มี debug allocator)
