---
trigger: always_on
---

# Compare Rust / Go / Zig — Project Structure Rules

## โครงสร้างมาตรฐานสำหรับทุกโปรเจกต์

โครงสร้าง **repository ระดับบน**:

```
compare-rust-go-zig/           ← repo root
├── <project-name>/
├── <project-name>/
└── .gitignore
```

ทุกโปรเจกต์ต้องมีโครงสร้างดังนี้:

```
<project-name>/
├── go/
│   ├── main.go         # Entry point
│   ├── go.mod          # module: <project-name>
│   └── Dockerfile      # Multi-stage build → debian:bookworm-slim
├── rust/
│   ├── src/
│   │   └── main.rs     # Entry point
│   ├── Cargo.toml
│   └── Dockerfile      # Multi-stage build → debian:bookworm-slim
├── zig/
│   ├── src/
│   │   └── main.zig    # Entry point
│   ├── build.zig       # Zig 0.15+ format (createModule + root_module)
│   └── Dockerfile      # Multi-stage build → debian:bookworm-slim
├── test-data/           # ไฟล์ media สำหรับทดสอบ (gitignored — ไม่ commit)
│   └── sample.mp4
├── benchmark/
│   └── run.sh           # script สำหรับวัด performance — รองรับ --docker flag
└── README.md            # คำแนะนำ build/run + ตาราง comparison
```

> **test-data rule**: แต่ละ project มี `test-data/` เป็นของตัวเอง ไม่ใช้ symlink  
> ไฟล์ media (`.mp4`, `.mkv` ฯลฯ) ถูก gitignore — ต้อง generate เองด้วย ffmpeg หลัง clone  
> `ffmpeg -f lavfi -i testsrc=duration=30:size=640x360:rate=25 -pix_fmt yuv420p test-data/sample.mp4`

---

## Go Version Rules

- ใช้ `go mod init <project-name>` ใน `go/` directory
- ถ้าใช้ CGO ให้ตั้ง cgo comment ก่อน `import "C"` เสมอ
- build ด้วย: `unset GOROOT && go build -o ../bin/<name>-go .`
- ต้อง `unset GOROOT` ก่อน build เสมอ (แก้ปัญหา Go version mismatch บนเครื่องนี้)
- การ output ไฟล์ผลลัพธ์: ใช้ format PPM (`.ppm`) เป็นค่าเริ่มต้นสำหรับ binary output

## Rust Rules

- ใช้ `ffmpeg-sys-next = "8.0"` สำหรับ FFmpeg 8.x (ไม่ใช้ `ffmpeg-next`)
- ต้องเพิ่ม `scopeguard = "1.2"` ใน dependencies ถ้าต้องการ RAII cleanup
- build ด้วย env vars:
  ```bash
  LLVM_CONFIG_PATH=/opt/homebrew/opt/llvm/bin/llvm-config \
  LIBCLANG_PATH=/opt/homebrew/opt/llvm/lib \
  PKG_CONFIG_PATH=/opt/homebrew/Cellar/ffmpeg/8.0.1_4/lib/pkgconfig \
  cargo build --release
  ```
- สำหรับ FFI unsafe code: ใช้ `scopeguard::guard()` pattern สำหรับ resource cleanup
- ไม่ใช้ `defer_on_drop!` macro เพราะ Rust borrow checker จะมีปัญหา
- ใช้ manual cleanup บน early-return paths แทน

## Zig Rules

- ใช้ Zig 0.15+ syntax สำหรับ `build.zig`:
  ```zig
  const exe_mod = b.createModule(.{
      .root_source_file = b.path("src/main.zig"),
      .target = target,
      .optimize = optimize,
  });
  const exe = b.addExecutable(.{
      .name = "<project-name>",
      .root_module = exe_mod,
  });
  ```
- Link libraries ด้วยชื่อไม่มี `lib` prefix: `exe.linkSystemLibrary("avformat")` ไม่ใช่ `"libavformat"`
- build ด้วย: `zig build -Doptimize=ReleaseFast`
- สำหรับ `defer` กับ C functions ที่รับ pointer: ใช้ `@constCast` แทน `@ptrCast`

---

## README.md มาตรฐาน

ทุก `README.md` ต้องมี:
1. **วัตถุประสงค์**: อธิบายสั้นๆ ว่าโปรเจกต์ทำอะไร + ทักษะที่ฝึก
2. **โครงสร้าง**: tree ของ directory
3. **Dependencies**: วิธีติดตั้ง (macOS/Linux)
4. **Build & Run**: คำสั่งสำหรับแต่ละภาษา
5. **Benchmark**: วิธีรัน `benchmark/run.sh`
6. **ตารางเปรียบเทียบ**: `| Aspect | Go | Rust | Zig |`
7. **หมายเหตุ**: จุดเด่น/จุดที่ต้องระวังของแต่ละภาษา

---

## benchmark/run.sh มาตรฐาน

### HTTP Throughput Projects (API Gateway ฯลฯ)
- ใช้ `wrk` เป็น benchmark tool: `wrk -t4 -c50 -d3s`
- สร้าง **Docker network** เพื่อให้ gateway และ backend คุยกันได้:
  ```bash
  docker network create gw-bench-net
  docker run --network gw-bench-net --name gw-mock-backend ...
  docker run --network gw-bench-net -p 8080:8080 ... "0.0.0.0:8080" "http://gw-mock-backend:3000"
  ```
- mock backend build เป็น Docker image inline ใน heredoc
- วัด **Binary Size** ด้วย `docker create` + `docker cp` + `wc -c` (ไม่ run container)
- Save ผลลัพธ์อัตโนมัติด้วย `exec > >(tee -a "$RESULT_FILE")` → `benchmark/results/result_<timestamp>.txt`
- cleanup: `docker network rm` หลัง benchmark เสร็จเสมอ

### Non-HTTP Projects (FFmpeg, CLI ฯลฯ)
- รัน 5 ครั้ง: 1 warm-up + 4 นับ average
- วัด **Time**: `$(date +%s%N)` nanoseconds → แปลงเป็น ms
- วัด **Memory**: `/usr/bin/time -l` (macOS) หรือ `/usr/bin/time -v` (Linux) — `parse_mem_kb()` helper รองรับทั้งคู่
- วัด **Binary Size**: `ls -lh`
- วัด **Code Lines**: `wc -l`

### ทั้งสองประเภท
- แสดงผล Avg / Min / Max แยก warm-up ออก
- ใช้ `SCRIPT_DIR` + `PROJECT_DIR` เพื่อรันจาก directory ใดก็ได้
- Build ทุก version ก่อน benchmark เสมอ

---

## Docker Standards

### Dockerfile Pattern (Multi-stage)
ทุก `go/Dockerfile`, `rust/Dockerfile`, `zig/Dockerfile` ใช้ multi-stage build:

```dockerfile
# Stage 1: builder — มี compiler + dev libs
FROM golang:1.23-bookworm AS builder
# ... build steps ...
RUN go build -o /out/<binary> .

# Stage 2: runtime — minimal image
FROM debian:bookworm-slim
COPY --from=builder /out/<binary> /usr/local/bin/<binary>
ENTRYPOINT ["<binary>"]
```

### Image Naming Convention
แต่ละ project ใช้ prefix ย่อ:
| Project | Go | Rust | Zig |
|---------|-----|------|-----|
| video-frame-extractor | `vfe-go` | `vfe-rust` | `vfe-zig` |
| hls-stream-segmenter | `hls-go` | `hls-rust` | `hls-zig` |
| subtitle-burn-in-engine | `sbe-go` | `sbe-rust` | `sbe-zig` |
| lightweight-api-gateway | `gw-go` | `gw-rust` | `gw-zig` |

### Docker Build Commands
```bash
# Build ทุก image สำหรับ project
docker build -t <prefix>-go   go/
docker build -t <prefix>-rust rust/
docker build -t <prefix>-zig  zig/

# Run benchmark ผ่าน Docker
bash benchmark/run.sh --docker

# Run benchmark แบบ local (default เดิม)
bash benchmark/run.sh
```

### Go Dockerfile Best Practices
- `CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w'` → static binary, stripped
- `mkdir -p /out` ก่อน build เสมอ
- แยก `ENTRYPOINT ["<binary>"]` กับ `CMD ["<default-args>"]` เสมอ

### Rust Dockerfile Best Practices
- ใช้ `rust:<version>-bookworm` เป็น builder (ไม่ใช้ `-alpine` เพราะ glibc/musl mismatch)
- dependency cache layer: copy `Cargo.toml Cargo.lock` → dummy `src/main.rs` → `cargo build --release` → copy real src → build
- `strip target/release/<binary>` หลัง build เพื่อลด binary size
- `Cargo.lock` ไม่ใส่ `*` glob — explicit เสมอ

### Zig + Zap Docker Notes
- Zap ใช้ `facil.io` เป็น shared lib → Dockerfile copy `libfacil.io.so` ไปที่ `/usr/local/lib/`
- ต้องรัน `ldconfig` ใน runtime stage เพื่อ register shared lib path
- บน Linux container ไม่มีปัญหา `DYLD_LIBRARY_PATH` (เป็น macOS-only)
- ใช้ `find .zig-cache -name 'libfacil.io.so*' -exec cp -L {} /out/ \;` เพื่อ copy .so

### Zig Builder — Download URL (0.15+)
URL format เปลี่ยนใน Zig 0.15+:
```
# เก่า (0.12–0.14): zig-linux-x86_64-<ver>.tar.xz
# ใหม่ (0.15+):     zig-<arch>-linux-<ver>.tar.xz
```
- ใช้ `ARG TARGETARCH` + shell conditional เพื่อรองรับ arm64/amd64:
```dockerfile
ARG TARGETARCH
RUN ZIG_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo "aarch64" || echo "x86_64") \
    && wget -q https://ziglang.org/download/0.15.2/zig-${ZIG_ARCH}-linux-0.15.2.tar.xz \
    && tar -xf zig-${ZIG_ARCH}-linux-0.15.2.tar.xz \
    && mv zig-${ZIG_ARCH}-linux-0.15.2 /usr/local/zig \
    && rm zig-${ZIG_ARCH}-linux-0.15.2.tar.xz
```
> **สำคัญ**: Docker Desktop on Mac = linux/arm64 → ต้องใช้ `aarch64` ไม่ใช่ `x86_64`

### FFmpeg Projects (Groups 1–2)

**Go CGO + FFmpeg — ต้องใช้ Alpine (ไม่ใช่ bookworm)**:
```dockerfile
FROM golang:1.2x-alpine AS builder
RUN apk add --no-cache pkgconfig ffmpeg-dev gcc musl-dev
# ...
FROM alpine:3.21
RUN apk add --no-cache ffmpeg-libs
```
> **สำคัญ**: Go CGO บน `bookworm arm64` มี known issue — `C.SwsContext` (opaque struct ใน libswscale) resolve ไม่ได้ → ใช้ `alpine` + `musl` เสมอสำหรับ Go FFmpeg projects

**Rust + FFmpeg — ใช้ bookworm (glibc)**:
- Builder: `rust:<ver>-bookworm` + `libavformat-dev libavcodec-dev libavutil-dev libswscale-dev clang llvm`
- Runtime: `debian:bookworm-slim` + `libavformat59 libavcodec59 libavutil57 libswscale6`

**Zig + FFmpeg — ใช้ bookworm (glibc)**:
- Builder: `debian:bookworm-slim` + FFmpeg dev libs + `ca-certificates` (จำเป็นก่อน wget Zig)
- Runtime: `debian:bookworm-slim` + runtime FFmpeg libs

**FFmpeg runtime package names บน bookworm arm64**:
| Library | Package |
|---------|---------|
| libavformat | `libavformat59` |
| libavcodec | `libavcodec59` |
| libavutil | `libavutil57` |
| libswscale | `libswscale6` |
| libavfilter | `libavfilter8` |

### Non-FFmpeg Projects (Groups 3+)
- Go/Rust: ไม่ต้อง install dev libs พิเศษ — builder images มี compiler พร้อมแล้ว
- Runtime stage: `debian:bookworm-slim` + `ca-certificates` (Go/Rust) หรือ + `ldconfig` (Zig+Zap)

---

## เกณฑ์เปรียบเทียบสำหรับทุกโปรเจกต์

| เกณฑ์ | วิธีวัด |
|-------|---------|
| **Performance** | Avg/Min/Max ms (ตัด warm-up run ออก) |
| **Memory** | Peak RSS KB จาก `/usr/bin/time -l` |
| **Binary Size** | `ls -lh <binary>` |
| **Code Lines** | `wc -l <source>` |
| **Build Time** | เวลา build ครั้งแรก (cold) |

---

## จุดเน้นของแต่ละภาษาตาม Project Group

### กลุ่มที่ 1: Video & Media Processing
- **Go**: CGO + FFmpeg, Concurrency สำหรับ parallel processing
- **Rust**: Memory Safety ใน buffer/frame management, FFI กับ FFmpeg
- **Zig**: Manual memory, C Interop ตรงผ่าน `@cImport`, binary เล็ก

### กลุ่มที่ 2: Infrastructure & Networking
- **Go**: Goroutines + Channels, `net/http`, เน้น throughput
- **Rust**: `tokio` async runtime, ownership ป้องกัน data races
- **Zig**: Low-level socket, manual event loop

### กลุ่มที่ 3: AI & Data Pipeline
- **Go**: Worker pool pattern, channel-based queue
- **Rust**: `tokio` + `reqwest`, type-safe pipeline
- **Zig**: Memory-efficient buffer, minimal allocations

### กลุ่มที่ 4: DevOps Tools
- **Go**: เน้น cross-compile, static binary, `os/exec`
- **Rust**: `clap` CLI, `serde` JSON, reliable binary
- **Zig**: Zero-dependency binary, smallest footprint

### กลุ่มที่ 5: Systems Fundamentals
- **Go**: GC behavior, `sync` package, interface-driven
- **Rust**: Ownership + lifetimes, no GC, zero-cost abstractions
- **Zig**: `comptime`, manual allocator, explicit memory layout

### กลุ่มที่ 6: Integration & Data
- **Go**: `net/http` client, JSON marshal/unmarshal, goroutines
- **Rust**: `reqwest`, `serde_json`, strong type safety
- **Zig**: Minimal HTTP, low-level string parsing

---

## Lessons Learned

### จาก video-frame-extractor
- **FFmpeg 8.0**: `avfft.h` ถูก removed → ต้องใช้ `ffmpeg-sys-next = "8.0"` ไม่ใช่ 7.x
- **Zig 0.15**: `root_source_file` field ถูกแทนที่ด้วย `createModule()` + `root_module`
- **Go CGO**: ต้อง `unset GOROOT` ถ้ามีหลาย Go versions ในเครื่อง
- **Zig const pointer**: ใช้ `@constCast` สำหรับ C functions ที่รับ non-const pointer
- **Binary size**: Zig (278KB) < Go (2.85MB) สำหรับ FFmpeg-linked binary
- **Runtime**: ทุกภาษาใช้เวลา ~42-50ms สำหรับ FFmpeg decode → FFmpeg เป็น bottleneck หลัก

### จาก lightweight-api-gateway
- **Alpine ≠ glibc**: Rust/Go binary ที่ build บน `bookworm` จะ crash บน Alpine เพราะ musl/glibc mismatch → ใช้ `debian:bookworm-slim` เสมอ
- **Zig 0.15 `build.zig.zon`**: ต้องมี `.fingerprint` field และ `.name` ต้องเป็น bare identifier (underscore ไม่ใช่ hyphen)
  ```zig
  .name = .lightweight_api_gateway,  // ✓
  .name = "lightweight-api-gateway",  // ✗ (Zig 0.15 error)
  ```
- **Zap version matrix**:
  | Zap | Zig |
  |-----|-----|
  | v0.9.x | 0.12 |
  | v0.10.x | 0.14 |
  | v0.11.x | 0.15+ |
- **Zap callback signature**: `fn onRequest(r: zap.Request) anyerror!void` (ไม่ใช่ `void`)
- **Docker Desktop on Mac**: runs linux/arm64 → ต้องใช้ `zig-aarch64-linux` ไม่ใช่ `zig-x86_64-linux`
- **Docker network สำหรับ benchmark**: gateway ต้องอยู่ใน network เดียวกับ mock backend เพื่อใช้ container DNS
- **Binary size วัดใน Docker**: ใช้ `docker create` + `docker cp` + `wc -c` — ไม่ใช้ `docker run du` (เพราะ ENTRYPOINT เป็น binary ไม่ใช่ shell)
- **Rust SocketAddr**: `:8080` parse ไม่ได้ → ต้องแปลงเป็น `0.0.0.0:8080` ก่อน
