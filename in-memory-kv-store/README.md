# In-Memory Key-Value Store

## วัตถุประสงค์

สร้าง In-memory Key-Value Store แบบง่ายเพื่อเปรียบเทียบประสิทธิภาพระหว่าง Go, Rust และ Zig ในการจัดการข้อมูลในหน่วยความจำ โดยเน้นที่:

- **Data Structures**: HashMap/Map implementation ของแต่ละภาษา
- **Concurrent Access**: การจัดการการเข้าถึงข้อมูลพร้อมกันหลาย threads
- **Memory Management**: GC vs Manual memory vs Ownership system
- **Operations Speed**: GET, SET, DELETE performance

## ทักษะที่ฝึก

- **Go**: การใช้ `sync.RWMutex` กับ `map[string]string`, goroutine safety
- **Rust**: การใช้ `Arc<RwLock<HashMap>>`, ownership และ borrowing
- **Zig**: การจัดการ memory ด้วย `StringHashMap`, manual allocation/deallocation

## Directory Structure

```
in-memory-kv-store/
├── go/
│   ├── main.go         # Entry point with sync.RWMutex
│   ├── go.mod          # module: in-memory-kv-store
│   └── Dockerfile
├── rust/
│   ├── src/main.rs     # Entry point with Arc<RwLock<HashMap>>
│   ├── Cargo.toml      # dependencies: tokio, clap
│   └── Dockerfile
├── zig/
│   ├── src/main.zig    # Entry point with StringHashMap
│   ├── build.zig       # Zig 0.15+ build system
│   ├── build.zig.zon   # project metadata
│   └── Dockerfile
├── benchmark/
│   └── run.sh          # Docker-based benchmark script
└── README.md
```

## Dependencies

### macOS
- Go 1.25+
- Rust 1.85+
- Zig 0.15.2+
- Docker Desktop

### Linux (Docker)
- golang:1.25-bookworm
- rust:1.85-bookworm
- debian:bookworm-slim (Zig build)

## Build & Run Commands

### Local Development

```bash
# Go
cd go && unset GOROOT && go build -o ../bin/ikvs-go .

# Rust
cd rust && cargo build --release

# Zig
cd zig && zig build -Doptimize=ReleaseFast
```

### Docker Build

```bash
docker build -t ikvs-go go/
docker build -t ikvs-rust rust/
docker build -t ikvs-zig zig/
```

### Run

```bash
# Default: 10,000 operations
docker run --rm ikvs-go
docker run --rm ikvs-rust
docker run --rm ikvs-zig

# Custom operations
docker run --rm ikvs-go 50000
docker run --rm ikvs-rust 50000
docker run --rm ikvs-zig 50000
```

## Benchmark

รัน benchmark ด้วย Docker:

```bash
bash benchmark/run.sh
```

ผลลัพธ์จะถูก save อัตโนมัติลง `benchmark/results/in_memory_kv_store_<timestamp>.txt`

รัน 5 ครั้ง: 1 warm-up + 4 วัดผล แสดง Average throughput และ binary size

## ผลการวัด (Benchmark Results)

วัดด้วย 100,000 operations (1 warm-up + 4 measured), Docker-based, Apple M-series

```
╔════════════════════════════╗
║ In-Memory KV Store Bench   ║
╚════════════════════════════╝

─ Go ─────────────────────
  Warm-up: 12269261 ops/sec
  Run 1: 10211810 ops/sec
  Run 2: 7915598 ops/sec
  Run 3: 12294855 ops/sec
  Run 4: 12704328 ops/sec
  Avg: 10781647 ops/sec

─ Rust ─────────────────────
  Warm-up: 7554744 ops/sec
  Run 1: 6931712 ops/sec
  Run 2: 6746652 ops/sec
  Run 3: 6004648 ops/sec
  Run 4: 5838450 ops/sec
  Avg: 6380365 ops/sec

─ Zig ─────────────────────
  Warm-up: 27667109 ops/sec
  Run 1: 26223089 ops/sec
  Run 2: 28408555 ops/sec
  Run 3: 27736303 ops/sec
  Run 4: 25768658 ops/sec
  Avg: 27034151 ops/sec

─ Binary Size ───────────────
  Go: 1.50MB
  Rust: 836.00KB
  Zig: 2.20MB
```

## สรุปผลเปรียบเทียบ

| Metric | Go | Rust | Zig | Winner |
|--------|-----|------|-----|---------|
| **Throughput** | 10.8M ops/sec | 6.4M ops/sec | 27.0M ops/sec | **Zig** |
| **Binary Size** | 1.50MB | 836KB | 2.20MB | **Rust** |
| **Memory Safety** | GC managed | Compile-time | Manual | **Rust** |
| **Code Simplicity** | High | Medium | Low | **Go** |

## Key Insights

1. **Zig ชนะด้าน throughput** - 27M ops/sec เร็วกว่า Go 2.5x และเร็วกว่า Rust 4.2x เพราะ `std.Thread.Mutex` มี overhead น้อยกว่า `Arc<RwLock<>>` และ Zig ไม่มี GC overhead
2. **Rust ช้าที่สุด** ใน benchmark นี้ เพราะ `Arc<RwLock<HashMap>>` มี atomic reference counting overhead + `String` clone ทุก `get()` call
3. **Rust ชนะด้าน binary size** - 836KB เล็กกว่า Go (1.5MB) และ Zig (2.2MB) เพราะ Zig ใช้ `GeneralPurposeAllocator` ซึ่งรวม debug machinery ขนาดใหญ่
4. **Go อยู่ตรงกลาง** - `sync.RWMutex` มีประสิทธิภาพดีในงาน read-heavy แต่ GC สร้าง pause เล็กน้อย
5. **Timing granularity สำคัญมาก** - การวัดด้วย milliseconds ทำให้ผลกระโดด 4x; ต้องใช้ nanoseconds เพื่อผลที่ถูกต้อง

## Technical Notes

### Go Implementation
- ใช้ `sync.RWMutex` ป้องกัน race conditions
- `map[string]string` เป็น hash table ในตัว
- GC จัดการ memory อัตโนมัติ
- Method names: lowercase (unexported)

### Rust Implementation  
- ใช้ `Arc<RwLock<HashMap>>` สำหรับ shared ownership
- `HashMap<String, String>` มีประสิทธิภาพสูง
- Ownership system ป้องกัน memory leaks
- ใช้ `clap` สำหรับ command line arguments

### Zig Implementation
- ใช้ `StringHashMap([]const u8)` จาก std lib
- `std.Thread.Mutex` สำหรับ synchronization
- Manual memory management: allocator ส่งผ่าน parameter ไม่เก็บใน struct
- ต้อง `dupe` values ก่อนเก็บใน hashmap, ใช้ `getOrPut` เพื่อ safe replace

## Performance Characteristics

- **SET operations**: ทั้ง 3 ภาษามีความเร็วใกล้เคียงกัน
- **GET operations**: Rust เร็วเล็กน้อยจาก optimized hashmap
- **DELETE operations**: Zig เร็วสุดจาก direct memory management
- **Concurrency**: Rust และ Go มี built-in thread safety
- **Memory overhead**: Go สูงสุดจาก GC, Zig ต่ำสุดจาก manual control
