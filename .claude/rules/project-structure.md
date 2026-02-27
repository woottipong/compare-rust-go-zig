# Compare Rust / Go / Zig — Project Structure & Code Patterns

## โครงสร้างมาตรฐานสำหรับทุกโปรเจกต์

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
├── test-data/           # gitignored
├── benchmark/
│   └── run.sh           # Docker-based เสมอ
└── README.md
```

---

## ⚠️ MANDATORY: Benchmark ต้องรันผ่าน Docker เสมอ

**กฎนี้บังคับสำหรับทุก AI ที่มาทำงานใน project นี้:**

- `benchmark/run.sh` **ต้องใช้ Docker** — build image ก่อนแล้วค่อยรัน container
- ห้าม benchmark ด้วย local binary โดยตรง
- ก่อนรัน benchmark ตรวจสอบ: `docker info`
- image naming: `<prefix>-go`, `<prefix>-rust`, `<prefix>-zig`
- mount test-data: `-v "$INPUT_DIR":/data:ro`
- capture stdout+stderr: `2>&1` (Zig ใช้ stderr)
- parse output: `awk -F': ' '{print $2}'`
- บันทึกผล: `benchmark/results/` เสมอ

---

## ⚠️ MANDATORY: Code Refactor Patterns

**กฎนี้บังคับสำหรับทุก AI ที่มาทำงานใน project นี้:**

### Shared Pattern (ทุกภาษา)

1. **Helper function สำหรับ duration → bytes**
   - Go: `func bytesForMs(durationMs int) int`  
   - Rust: `fn bytes_for_ms(duration_ms: u64) -> usize`  
   - Zig: `fn bytesForMs(duration_ms: usize) usize`

2. **Stats struct แยกออกมาเสมอ** — ไม่ใช้ closure-captured mutable variables
   - มี method `avgLatencyMs()` และ `throughput()`
   - เก็บ `processing_time` แยกจาก chunker

3. **แยก helper functions** — `printConfig(...)`, `printStats(...)`, `simulateRealtimeInput(...)`

4. **`main()` ต้องกระชับ** — แค่ orchestrate: read → config → chunker → simulate → stats → print

### Go Patterns

```go
// ใช้ integer milliseconds สำหรับ duration constants
const chunkDurationMs = 25

// helper function ป้องกัน float truncation
func chunkSamples(durationMs int) int {
    return sampleRate * durationMs / 1000
}

// startProcessor คืน channel แทนการใช้ closure capture
func (ac *AudioChunker) startProcessor() <-chan Stats { ... }
```

- method names: **lowercase** (unexported) — `newAudioChunker`, `processAudio`, `finalize`, `startProcessor`
- error wrapping: `fmt.Errorf("context: %w", err)` เสมอ

### Rust Patterns

```rust
// constants เป็น u64 ms เสมอ (ไม่ใช่ Duration ใน const สำหรับคำนวณ samples)
const CHUNK_DURATION_MS: u64 = 25;

// helper ป้องกัน as_secs() truncation bug
fn bytes_for_ms(duration_ms: u64) -> usize { ... }

// processor เป็น free function คืน JoinHandle<Stats>
fn start_processor(receiver: mpsc::Receiver<AudioChunk>) -> thread::JoinHandle<Stats> { ... }

// sender.send() ใช้ .is_err() ไม่ใช่ .unwrap()
if self.sender.send(chunk).is_err() { break; }
```

- ลบ empty methods ออก (เช่น `fn finalize() {}`)
- error messages ใน `map_err`: `format!("context: {}", e)`

### Zig Patterns

```zig
// constants เป็น ms ทุกอัน + precompute ns สำหรับ sleep
const INPUT_INTERVAL_MS = 10;
const INPUT_INTERVAL_NS = INPUT_INTERVAL_MS * std.time.ns_per_ms;

// helper function
fn bytesForMs(duration_ms: usize) usize { ... }

// AudioChunk ไม่เก็บ allocator — เป็น stack value ที่ส่งผ่าน callback
const AudioChunk = struct { data: []const u8, timestamp: ..., index: usize };

// overlap shift ใช้ std.mem.copyForwards (ปลอดภัยกับ overlapping memory)
std.mem.copyForwards(u8, dst, src);

// Stats เป็น struct ที่มี method
const Stats = struct {
    fn avgLatencyMs(self: Stats) f64 { ... }
    fn throughput(self: Stats, processing_ns: u64) f64 { ... }
};
```

---

## Statistics Output Format มาตรฐาน

```
--- Statistics ---
Total chunks: <N>
Processing time: <X.XXX>s
Average latency: <X.XXX>ms
Throughput: <X.XX> chunks/sec
```

---

## Go Version Rules

- build: `unset GOROOT && go build -o ../bin/<name>-go .`
- ต้อง `unset GOROOT` ก่อน build เสมอ

## Rust Rules

- **Bug**: `Duration::as_secs()` truncates → ใช้ `as_millis() / 1000` หรือ integer ms constants เสมอ
- สำหรับ FFI: `scopeguard::guard()` pattern

## Zig Rules

- Zig 0.15+ build.zig: `createModule()` + `root_module`
- Link libraries ไม่มี `lib` prefix
- `std.debug.print` → stderr (benchmark ต้อง `2>&1`)

---

## Image Naming Convention

| Project | Go | Rust | Zig |
|---------|-----|------|-----|
| video-frame-extractor | `vfe-go` | `vfe-rust` | `vfe-zig` |
| hls-stream-segmenter | `hls-go` | `hls-rust` | `hls-zig` |
| subtitle-burn-in-engine | `sbe-go` | `sbe-rust` | `sbe-zig` |
| lightweight-api-gateway | `gw-go` | `gw-rust` | `gw-zig` |
| realtime-audio-chunker | `rac-go` | `rac-rust` | `rac-zig` |

---

## Docker Standards

### Go Dockerfile
- `CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w'`
- `mkdir -p /out` ก่อน build

### Rust Dockerfile
- `rust:<version>-bookworm` builder
- dependency cache layer ก่อน copy real source
- `strip` binary หลัง build

### Zig Dockerfile
- `debian:bookworm-slim` + wget Zig tarball
- `ARG TARGETARCH`: `arm64` → `aarch64`, else → `x86_64`
- URL: `zig-${ZIG_ARCH}-linux-<ver>.tar.xz`

### FFmpeg (Go CGO)
- Alpine เท่านั้น (bookworm arm64 มี `C.SwsContext` issue)

### FFmpeg runtime (bookworm arm64)
`libavformat59`, `libavcodec59`, `libavutil57`, `libswscale6`, `libavfilter8`

---

## benchmark/run.sh มาตรฐาน

### HTTP Throughput
- `wrk -t4 -c50 -d3s` + Docker network
- cleanup: `docker network rm` เสมอ

### Non-HTTP (Audio, CLI, FFmpeg)
- รัน 1 ครั้งต่อ language
- parse: `awk -F': ' '{print $2}'` จาก `2>&1`
- Binary Size: `docker create` + `docker cp` + `wc -c`
- Code Lines: `wc -l <source>`

### ทั้งสอง
- `SCRIPT_DIR` + `PROJECT_DIR`
- Build ก่อน: แสดง `✓` หรือ `✗ build failed`
- Save: `exec > >(tee -a "$RESULT_FILE")` → `benchmark/results/<project>_<timestamp>.txt`
