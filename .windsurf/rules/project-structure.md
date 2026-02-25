---
trigger: always_on
---

# Compare Rust / Go / Zig — Project Structure Reference

## Directory Layout

```
<project-name>/
├── go/
│   ├── main.go         # Entry point
│   ├── go.mod          # module: <project-name>
│   └── Dockerfile
├── rust/
│   ├── src/main.rs
│   ├── Cargo.toml
│   └── Dockerfile
├── zig/
│   ├── src/main.zig
│   ├── build.zig       # Zig 0.15+ (createModule + root_module)
│   └── Dockerfile
├── test-data/           # gitignored — generate ด้วย ffmpeg หลัง clone
├── benchmark/
│   └── run.sh
└── README.md
```

> `test-data/` เป็นของแต่ละ project เอง ไม่ใช้ symlink  
> `ffmpeg -f lavfi -i testsrc=duration=30:size=640x360:rate=25 -pix_fmt yuv420p test-data/sample.mp4`

---

## Build Commands (Local)

### Go
```bash
unset GOROOT && go build -o ../bin/<name>-go .
```
- `unset GOROOT` เสมอ (แก้ Go version mismatch บนเครื่องนี้)
- CGO: ตั้ง comment ก่อน `import "C"` เสมอ
- binary output format: PPM (`.ppm`) สำหรับ image output

### Rust
```bash
LLVM_CONFIG_PATH=/opt/homebrew/opt/llvm/bin/llvm-config \
LIBCLANG_PATH=/opt/homebrew/opt/llvm/lib \
PKG_CONFIG_PATH=/opt/homebrew/Cellar/ffmpeg/8.0.1_4/lib/pkgconfig \
cargo build --release
```
- FFmpeg: `ffmpeg-sys-next = "8.0"` (ไม่ใช้ `ffmpeg-next`)
- RAII cleanup: `scopeguard = "1.2"` + `scopeguard::guard()` pattern
- ไม่ใช้ `defer_on_drop!` macro (borrow checker ปัญหา) → manual cleanup บน early-return paths

### Zig
```bash
zig build -Doptimize=ReleaseFast
```
- `build.zig` ใช้ Zig 0.15+ syntax: `createModule()` + `root_module`
- Link libs ไม่มี `lib` prefix: `exe.linkSystemLibrary("avformat")`
- `defer` กับ C pointer: ใช้ `@constCast` ไม่ใช่ `@ptrCast`

---

## benchmark/run.sh Reference

### Non-HTTP (CLI, FFmpeg, processing)
```bash
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
RESULT_FILE="$SCRIPT_DIR/results/<project>_$(date +%Y%m%d_%H%M%S).txt"
exec > >(tee -a "$RESULT_FILE")

# build
docker build -q -t <prefix>-go   "$PROJECT_DIR/go/"
docker build -q -t <prefix>-rust "$PROJECT_DIR/rust/"
docker build -q -t <prefix>-zig  "$PROJECT_DIR/zig/"

# run (5 runs: 1 warm-up + 4 measured)
output=$(docker run --rm -v "$INPUT_DIR":/data:ro <image> /data/<file> 2>&1)
throughput=$(echo "$output" | grep "Throughput:" | awk -F': ' '{print $2}')

# binary size
cid=$(docker create <image>)
size=$(docker cp "$cid:/usr/local/bin/<binary>" - | wc -c)
docker rm "$cid"
```

### HTTP Throughput (API Gateway, Proxy)
```bash
docker network create bench-net
docker run -d --network bench-net --name mock-backend <backend-image>
docker run -d --network bench-net -p 8080:8080 <gateway-image> "0.0.0.0:8080" "http://mock-backend:3000"
wrk -t4 -c50 -d3s http://localhost:8080/
docker network rm bench-net   # cleanup เสมอ
```
- mock backend: build inline Dockerfile ใน heredoc
- parse output: `awk -F': ' '{print $2}'` เสมอ

---

## README.md มาตรฐาน

ทุก project ต้องมี:
1. วัตถุประสงค์ + ทักษะที่ฝึก
2. Directory tree
3. Dependencies (macOS/Linux)
4. Build & Run commands
5. **Benchmark section** — ระบุ:
   - `bash benchmark/run.sh`
   - "`ผลลัพธ์จะถูก save อัตโนมัติลง benchmark/results/...`"
   - Non-HTTP: ระบุว่า "รัน 5 ครั้ง: 1 warm-up + 4 วัดผล"
6. **ผลการวัด (Benchmark Results)** — raw output จาก run.sh จริง:
   ```
   ╔═══════════════════╗
   ║  <Project> Bench  ║
   ╚═══════════════════╝
   ── Go   ─────────────
     Run 1 (warm-up): Xms
     Run 2           : Xms
     ...
     Avg: Xms  |  Min: Xms  |  Max: Xms
   ── Binary Size ──────
     Go  : X.XMB
     Rust: XXXKB
     Zig : X.XMB
   ```
   - HTTP projects: แสดง `Requests/sec` + `Avg Latency` ต่อภาษา
7. ตาราง `| Metric | Go | Rust | Zig |` summary
8. Key insight — ภาษาไหนชนะ + เหตุผล

---

## เกณฑ์เปรียบเทียบ

| เกณฑ์ | วิธีวัด |
|-------|---------|
| **Performance** | Avg/Min/Max (ตัด 1 warm-up run ออก) |
| **Memory** | Peak RSS KB จาก `docker stats` หรือ `/usr/bin/time` |
| **Binary Size** | `docker create` + `docker cp` + `wc -c` |
| **Code Lines** | `wc -l <source>` |

---

## จุดเน้นของแต่ละภาษาตาม Project Group

| กลุ่ม | Go | Rust | Zig |
|-------|-----|------|-----|
| **1 Media (FFmpeg)** | CGO + goroutines | FFI + memory safety | `@cImport`, manual memory |
| **2 Networking** | `net/http`, goroutines | `tokio` async | raw socket, manual event loop |
| **3 AI/Data** | worker pool, channels | `tokio` + type-safe pipeline | memory-efficient buffer |
| **4 DevOps** | static binary, `os/exec` | `clap`, `serde` | zero-dependency, smallest binary |
| **5 Systems** | GC behavior, `sync` | ownership + lifetimes | `comptime`, manual allocator |
| **6 Integration** | `net/http` client | `reqwest`, `serde_json` | minimal HTTP, string parsing |
| **7 Networking (low)** | raw UDP/TCP | `tokio` UDP | raw socket, binary protocol |
| **8 Image (pure algo)** | math-heavy loops | SIMD-friendly Rust | `comptime` lookup tables |
| **9 Data Engineering** | streaming I/O | zero-copy parsing | columnar format, bit ops |

---

## Zig + Zap (HTTP framework)

- Zap ใช้ `facil.io` เป็น shared lib → copy `libfacil.io.so` ไปที่ `/usr/local/lib/` + `ldconfig`
- `find .zig-cache -name 'libfacil.io.so*' -exec cp -L {} /out/ \;`
- Zap version matrix: v0.9→Zig 0.12, v0.10→Zig 0.14, v0.11→Zig 0.15+
- callback signature: `fn onRequest(r: zap.Request) anyerror!void`

---

## Rust + FFmpeg

- Builder: `rust:1.83-bookworm` + `libavformat-dev libavcodec-dev libavutil-dev libswscale-dev clang llvm`
- Runtime: `debian:bookworm-slim` + `libavformat59 libavcodec59 libavutil57 libswscale6`
- `Cargo.lock` — explicit, ไม่ใช้ glob `*`
