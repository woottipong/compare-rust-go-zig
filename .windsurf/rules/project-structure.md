---
trigger: always_on
---

# Compare Rust / Go / Zig — Project Structure Rules

## โครงสร้างมาตรฐานสำหรับทุกโปรเจกต์

ทุกโปรเจกต์ต้องมีโครงสร้างดังนี้:

```
<project-name>/
├── go/
│   ├── main.go         # Entry point
│   └── go.mod          # module: <project-name>
├── rust/
│   ├── src/
│   │   └── main.rs     # Entry point
│   └── Cargo.toml
├── zig/
│   ├── src/
│   │   └── main.zig    # Entry point
│   └── build.zig       # Zig 0.15+ format (createModule + root_module)
├── test-data/           # input files สำหรับทดสอบ
├── benchmark/
│   └── run.sh           # script สำหรับวัด performance ทั้ง 3 ภาษา
└── README.md            # คำแนะนำ build/run + ตาราง comparison
```

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

- รับ args: `$1` = input file, `$2` = parameter (project-specific)
- รัน 5 ครั้ง: 1 warm-up + 4 นับ average
- วัด **Time**: `$(date +%s%N)` nanoseconds → แปลงเป็น ms
- วัด **Memory**: `/usr/bin/time -l` → `maximum resident set size` (macOS)
- วัด **Binary Size**: `ls -lh`
- วัด **Code Lines**: `wc -l`
- แสดงผล Avg / Min / Max แยก warm-up ออก
- ใช้ `SCRIPT_DIR` + `PROJECT_DIR` เพื่อรันจาก directory ใดก็ได้
- Build ทุก version ก่อน benchmark เสมอ

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
