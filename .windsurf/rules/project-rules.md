---
description: Compare Rust / Go / Zig — Mandatory project rules for all AI assistants
trigger: always_on
---

# Project Rules: Compare Rust / Go / Zig

## ⚠️ Checklist สำหรับ Project ใหม่ทุกตัว

ก่อน implement ต้องมีครบทุกข้อ:

- [ ] โครงสร้าง `go/`, `rust/`, `zig/`, `test-data/`, `benchmark/run.sh`, `README.md`
- [ ] Docker image naming: `<prefix>-go`, `<prefix>-rust`, `<prefix>-zig` — เพิ่มใน table ด้านล่าง
- [ ] `benchmark/run.sh` — Docker-based เสมอ, auto-save ผลใน `benchmark/results/`
- [ ] Statistics output format ตรงกันทั้ง 3 ภาษา (ดู format ด้านล่าง)
- [ ] `main()` กระชับ — orchestrate เท่านั้น, logic แยกออกเป็น functions/structs
- [ ] `README.md` มีตารางผลเปรียบเทียบ + key insight

---

## ⚠️ MANDATORY: Benchmark ต้องรันผ่าน Docker เสมอ

- ห้าม benchmark ด้วย local binary (local dev เท่านั้นที่ยกเว้น)
- ก่อนรัน: `docker info` เพื่อตรวจสอบ Docker daemon
- mount test-data: `-v "$INPUT_DIR":/data:ro`
- capture stdout+stderr: `2>&1` (Zig ใช้ stderr)
- parse output: `awk -F': ' '{print $2}'`
- auto-save: `exec > >(tee -a "$RESULT_FILE")` → `benchmark/results/<project>_<timestamp>.txt`

### Non-HTTP Projects (CLI, FFmpeg, processing tools)
- 5 runs: 1 warm-up + 4 measured → แสดง Avg/Min/Max
- วัด binary size: `docker create` + `docker cp` + `wc -c`

### HTTP Throughput Projects
- `wrk -t4 -c50 -d3s` + Docker network
- cleanup `docker network rm` เสมอ

---

## Statistics Output Format (ทุกภาษาต้องตรงกัน)

```
--- Statistics ---
Total processed: <N>
Processing time: <X.XXX>s
Average latency: <X.XXX>ms
Throughput: <X.XX> items/sec
```

> field names ปรับตาม domain (chunks/requests/lines ฯลฯ) แต่โครงสร้างเหมือนกัน

---

## Code Principles (ทุกภาษา)

1. **`main()` orchestrates only** — read args → config → init → run → print stats
2. **Stats struct แยกออกมาเสมอ** — มี method `avgLatencyMs()` / `throughput()` — ไม่ใช้ closure-captured mutable vars
3. **Helper functions แยกชัดเจน** — `printConfig()`, `printStats()`, domain logic ต่างหาก
4. **ไม่คำนวณ inline ซ้ำๆ** — wrap ใน helper function เสมอ

### Go
- method names lowercase (unexported) เสมอ
- error wrapping: `fmt.Errorf("context: %w", err)`
- ใช้ integer ms constants แทน `time.Duration.Seconds()` เมื่อคำนวณ samples/bytes

### Rust
- ใช้ integer ms constants แทน `Duration::as_secs()` (truncates sub-second → bug)
- ไม่ใช้ `.unwrap()` บน channel send — ใช้ `.is_err()` แทน
- ลบ empty methods ออก

### Zig
- `std.debug.print` → stderr, ต้องใช้ `2>&1` ใน benchmark
- buffer shift ใช้ `std.mem.copyForwards` ป้องกัน overlapping memory
- struct ไม่เก็บ allocator — ส่งผ่าน parameter แทน

---

## Docker Image Naming

| Project | Go | Rust | Zig |
|---------|-----|------|-----|
| video-frame-extractor | `vfe-go` | `vfe-rust` | `vfe-zig` |
| hls-stream-segmenter | `hls-go` | `hls-rust` | `hls-zig` |
| subtitle-burn-in-engine | `sbe-go` | `sbe-rust` | `sbe-zig` |
| high-perf-reverse-proxy | `rp-go` | `rp-rust` | `rp-zig` |
| lightweight-api-gateway | `gw-go` | `gw-rust` | `gw-zig` |
| realtime-audio-chunker | `rac-go` | `rac-rust` | `rac-zig` |
| custom-log-masker | `clm-go` | `clm-rust` | `clm-zig` |
| vector-db-ingester | `vdi-go` | `vdi-rust` | `vdi-zig` |
| local-asr-llm-proxy | `asr-go` | `asr-rust` | `asr-zig` |
| log-aggregator-sidecar | `las-go` | `las-rust` | `las-zig` |

> Project ใหม่: เพิ่ม row นี้ก่อน implement

---

## Dockerfile Standards

### Go (non-CGO)
```dockerfile
FROM golang:1.25-bookworm AS builder
WORKDIR /src
COPY . .
RUN mkdir -p /out && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /out/<binary> .

FROM debian:bookworm-slim
COPY --from=builder /out/<binary> /usr/local/bin/<binary>
ENTRYPOINT ["/usr/local/bin/<binary>"]
```
> ต้องมี `mkdir -p /out` ก่อน build เสมอ — ขาดแล้ว build fail
> ENTRYPOINT ใช้ absolute path เสมอ

### Go + FFmpeg (CGO) — ใช้ Alpine เท่านั้น
```dockerfile
FROM golang:1.25-alpine AS builder
RUN apk add --no-cache pkgconfig ffmpeg-dev gcc musl-dev

FROM alpine:3.21
RUN apk add --no-cache ffmpeg-libs
```
> bookworm arm64 มี `C.SwsContext` opaque struct issue → Alpine + musl เท่านั้น

### Rust
```dockerfile
FROM rust:1.85-bookworm AS builder
WORKDIR /src
# 1) dependency cache layer
COPY Cargo.toml Cargo.lock ./
RUN mkdir -p src && echo 'fn main(){}' > src/main.rs \
    && cargo build --release \
    && rm src/main.rs
# 2) build real binary
COPY src ./src
RUN touch src/main.rs \
    && cargo build --release \
    && strip target/release/<binary-name-from-Cargo.toml>

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /src/target/release/<binary-name-from-Cargo.toml> /usr/local/bin/<binary>
ENTRYPOINT ["/usr/local/bin/<binary>"]
```
> `touch src/main.rs` จำเป็นเพื่อ invalidate build cache ไม่ให้ใช้ dummy binary
> binary name ใน `strip` และ `COPY` ต้องตรงกับ `name` ใน `Cargo.toml` **ทุกครั้ง**
> ใช้ `rust:1.85-bookworm` (ไม่ใช่ 1.83)

### Zig
```dockerfile
FROM debian:bookworm-slim AS builder
ARG TARGETARCH
RUN ZIG_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo "aarch64" || echo "x86_64") \
    && wget -q https://ziglang.org/download/0.15.2/zig-${ZIG_ARCH}-linux-0.15.2.tar.xz \
    && tar -xf zig-${ZIG_ARCH}-linux-0.15.2.tar.xz \
    && mv zig-${ZIG_ARCH}-linux-0.15.2 /usr/local/zig
```
> Docker Desktop on Mac = linux/arm64 → ต้องเป็น `aarch64`

### FFmpeg runtime packages (bookworm arm64)
`libavformat59 libavcodec59 libavutil57 libswscale6 libavfilter8`

---

## Known Bugs / Gotchas

| ภาษา | Bug | Fix |
|------|-----|-----|
| **Rust** | `Duration::as_secs()` truncates sub-second → value = 0 | ใช้ `as_millis() / 1000` หรือ integer ms constants |
| **Go** | `time.Duration.Seconds()` float → int truncation สำหรับ < 1s | ใช้ integer ms arithmetic |
| **Zig** | `std.debug.print` → stderr ไม่ใช่ stdout | benchmark script ต้อง `2>&1` |
| **Zig** | loop shift buffer ด้วย index อาจ overlap | ใช้ `std.mem.copyForwards` เสมอ |
| **Zig** | `build.zig.zon` `.name` ต้องเป็น bare identifier | `.name = .my_project` ไม่ใช่ `"my-project"` |
| **Rust** | `:8080` parse เป็น SocketAddr ไม่ได้ | ใช้ `0.0.0.0:8080` |
| **Go CGO + bookworm arm64** | `*C.SwsContext` field ใน struct resolve ไม่ได้ | ใช้ C helper wrapper function แทน หรือ Alpine |
| **Rust** | `reqwest` default feature ใช้ native-tls → ต้องการ `libssl3` ใน runtime | ใช้ `features = ["rustls-tls"], default-features = false` เสมอ |
| **Rust** | Dockerfile cache ใช้ dummy binary เก่า เพราะลืม `touch src/main.rs` | `touch src/main.rs` ก่อน `cargo build --release` รอบที่ 2 เสมอ |
| **Rust** | binary name ใน Dockerfile ไม่ตรงกับ `Cargo.toml` → ENTRYPOINT ไม่ได้ binary จริง | ตรวจ `name = "..."` ใน Cargo.toml ก่อน copy เสมอ |
| **Go** | `http.Response.Body` ไม่ถูก drain ก่อน close → connection ไม่ถูก reuse → port exhaustion | `io.Copy(io.Discard, resp.Body)` ก่อน `resp.Body.Close()` เสมอ |
| **Go** | `http.Client` ไม่มี `Transport` config → connection pool ไม่ทำงาน | เพิ่ม `Transport: &http.Transport{MaxIdleConnsPerHost: 100}` เสมอ |
| **Go** | CMD args ใน Dockerfile ไม่ตรงกับ `parseArgs()` | `CMD ["addr", "url"]` positional ต้องตรงกับ logic ใน code เสมอ |
| **Zig** | `std.ArrayList` ใน 0.15 เป็น unmanaged → `.init(allocator)` ไม่มีแล้ว | ใช้ `.{}` และส่ง allocator ใน ทุก method call |
| **Zig** | `std.time.sleep` ไม่มีใน 0.15 | ใช้ `std.Thread.sleep` |
| **Zig** | `json.stringifyAlloc` ไม่มีใน 0.15 | ใช้ `std.json.Stringify.valueAlloc(allocator, value, .{})` |
| **Zig** | `std.http.Client.open` ไม่มีใน 0.15 | ใช้ `client.fetch(.{ .location = .{ .url = ... }, .method = .POST, ... })` |
| **Zig** | `client.fetch` `response_writer` ต้องการ `*std.Io.Writer` | ใช้ `var aw: std.Io.Writer.Allocating = .init(allocator)` แล้วส่ง `&aw.writer` |
| **Zig** | free string literal → crash | ทุก field ใน struct ที่จะ `free` ต้อง allocate ด้วย `allocator.dupe` เสมอ แม้แต่ fallback value |
| **Zig** | `ArrayList.writer()` ใน 0.15 ต้องรับ allocator | `buf.writer(allocator)` ไม่ใช่ `buf.writer()` |

---

## Code Design Rules

### Go
- `http.Client` ใช้ร่วมกัน (shared) ต่อ worker — ไม่สร้างใหม่ต่อ request
- response body ต้อง drain + close เสมอ: `io.Copy(io.Discard, resp.Body); resp.Body.Close()`
- `parseArgs()` ต้องรองรับทั้ง positional args และ flags ให้ตรงกับ `CMD` ใน Dockerfile

### Rust
- ห้ามรวม HTTP client ไว้ใน `Stats` struct — แยกเป็น `AppState` หรือ struct ใหม่
- ห้ามใช้ `OnceLock` hack สำหรับ config — ส่งผ่าน state เสมอ
- `reqwest` ต้องใช้ `rustls-tls` เสมอ (ไม่ใช่ native-tls) เพื่อหลีกเลี่ยง libssl dependency
- `#[arg(long, action = ArgAction::SetTrue)]` สำหรับ boolean flag — ไม่ใช่ `default_value = "false"`

### Zig
- `std.http.Client` ถ้าใช้ใน request handler → สร้างใหม่ต่อ request (acceptable) หรือเก็บใน global state
- ทุก field ใน struct ที่ allocate บน heap ต้องมี `freeXxx()` function และต้อง `dupe` ทุก field รวมถึง fallback literals
