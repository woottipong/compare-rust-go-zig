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

- รับ args: `$1` = input file, `$2` = parameter (project-specific), `[--docker]` = docker mode
- รัน 5 ครั้ง: 1 warm-up + 4 นับ average
- วัด **Time**: `$(date +%s%N)` nanoseconds → แปลงเป็น ms
- วัด **Memory**: `/usr/bin/time -l` (macOS) หรือ `/usr/bin/time -v` (Linux) — `parse_mem_kb()` helper รองรับทั้งคู่
- วัด **Binary Size**: `ls -lh`
- วัด **Code Lines**: `wc -l`
- แสดงผล Avg / Min / Max แยก warm-up ออก
- ใช้ `SCRIPT_DIR` + `PROJECT_DIR` เพื่อรันจาก directory ใดก็ได้
- Build ทุก version ก่อน benchmark เสมอ
- รองรับ `--docker` flag: build Docker images แล้ว run ผ่าน `docker run`

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

### Zig + Zap Docker Notes
- Zap ใช้ `facil.io` เป็น shared lib → Dockerfile copy `.so` ไปไว้ใน `/usr/local/lib/facil/`
- ต้องรัน `ldconfig` ใน runtime stage เพื่อ register shared lib path
- บน Linux container ไม่มีปัญหา `DYLD_LIBRARY_PATH` (เป็น macOS-only)

### FFmpeg Projects (Groups 1–2)
- Builder stage ต้องติดตั้ง: `libavformat-dev libavcodec-dev libavutil-dev libswscale-dev`
- Runtime stage ติดตั้ง runtime libs เท่านั้น: `libavformat60 libavcodec60 libavutil58 libswscale7`
- Rust builder ต้องเพิ่ม `clang llvm` สำหรับ bindgen
- Zig builder ต้อง download `zig-linux-x86_64-0.15.0.tar.xz` จาก ziglang.org

### Non-FFmpeg Projects (Groups 3+)
- Go/Rust: ไม่ต้อง install dev libs พิเศษ — builder images มี compiler พร้อมแล้ว
- Runtime stage: `debian:bookworm-slim` เปล่าๆ (Go/Rust) หรือ + ldconfig (Zig+Zap)

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

## Lessons Learned จาก video-frame-extractor

- **FFmpeg 8.0**: `avfft.h` ถูก removed → ต้องใช้ `ffmpeg-sys-next = "8.0"` ไม่ใช่ 7.x
- **Zig 0.15**: `root_source_file` field ถูกแทนที่ด้วย `createModule()` + `root_module`
- **Go CGO**: ต้อง `unset GOROOT` ถ้ามีหลาย Go versions ในเครื่อง
- **Zig const pointer**: ใช้ `@constCast` สำหรับ C functions ที่รับ non-const pointer
- **Binary size**: Zig (278KB) < Go (2.85MB) สำหรับ FFmpeg-linked binary
- **Runtime**: ทุกภาษาใช้เวลา ~42-50ms สำหรับ FFmpeg decode → FFmpeg เป็น bottleneck หลัก
