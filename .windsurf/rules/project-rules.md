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
RUN mkdir -p /out
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /out/<binary> .

FROM debian:bookworm-slim
COPY --from=builder /out/<binary> /usr/local/bin/<binary>
ENTRYPOINT ["<binary>"]
```

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
FROM rust:1.83-bookworm AS builder
# dependency cache layer ก่อน (copy Cargo.toml + dummy main → build → copy real src → build)
RUN strip target/release/<binary>

FROM debian:bookworm-slim
```

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
