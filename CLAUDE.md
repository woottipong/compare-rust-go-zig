# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

A collection of 29 mini-projects each implemented in **Go**, **Rust**, and **Zig** for direct performance comparison across 10 domains (media, networking, AI/data, DevOps, systems, integration, low-level networking, image processing, data engineering, serialization & encoding). All benchmarks are Docker-based. Plus **websocket-public-chat** as an advanced multi-profile project (30 total).

## Build Commands

### Local builds (per language, inside project subdirectory)

```bash
# Go — always unset GOROOT first (fixes version mismatch on this machine)
unset GOROOT && go build -o ../bin/<name>-go .

# Rust — set env vars for FFmpeg projects
LLVM_CONFIG_PATH=/opt/homebrew/opt/llvm/bin/llvm-config \
LIBCLANG_PATH=/opt/homebrew/opt/llvm/lib \
PKG_CONFIG_PATH=/opt/homebrew/Cellar/ffmpeg/8.0.1_4/lib/pkgconfig \
cargo build --release

# Zig
zig build -Doptimize=ReleaseFast
# Debug build (no optimize flag)
zig build
```

### Run benchmarks (Docker required)

```bash
# Run benchmark for a single project
cd <project-name>
bash benchmark/run.sh
# Results auto-saved to: benchmark/results/<project>_<timestamp>.txt

# Verify Docker is running first
docker info
```

## Project Structure

Every project follows an identical layout:

```
<project-name>/
├── go/
│   ├── main.go       # Entry point (orchestrate only)
│   ├── go.mod
│   └── Dockerfile
├── rust/
│   ├── src/main.rs
│   ├── Cargo.toml
│   └── Dockerfile
├── zig/
│   ├── src/main.zig
│   ├── build.zig     # Zig 0.15+ syntax: createModule() + root_module
│   └── Dockerfile
├── test-data/        # gitignored — generate after clone
├── benchmark/
│   ├── run.sh        # Always Docker-based
│   └── results/
└── README.md
```

## Mandatory Standards

### Statistics output (identical across all 3 languages)

```
--- Statistics ---
Total processed: <N>
Processing time: <X.XXX>s
Average latency: <X.XXX>ms
Throughput: <X.XX> items/sec
```

Field names may adapt to domain (requests/chunks/lines) but structure is fixed.

### Code structure rules

- `main()` orchestrates only: read args → config → init → run → print stats
- Stats struct must be separate with `avgLatencyMs()` / `throughput()` methods
- No inline repeated calculations — wrap in helper functions

### Benchmark methodology

- **Non-HTTP projects**: 5 runs (1 warm-up + 4 measured) → report Avg/Min/Max
- **HTTP projects**: `wrk -t4 -c50 -d3s` + Docker network
- Zig writes stats to stderr → benchmark scripts must use `2>&1`
- Parse output with: `awk -F': ' '{print $2}'`

### Docker image naming: `<prefix>-go`, `<prefix>-rust`, `<prefix>-zig`

## Dockerfile Templates

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
> `mkdir -p /out` is required before the build step or it will fail.

### Go + FFmpeg (CGO) — Alpine only
```dockerfile
FROM golang:1.25-alpine AS builder
RUN apk add --no-cache pkgconfig ffmpeg-dev gcc musl-dev

FROM alpine:3.21
RUN apk add --no-cache ffmpeg-libs
```
> bookworm arm64 has a `C.SwsContext` opaque struct issue — use Alpine + musl only.

### Rust
```dockerfile
FROM rust:1.85-bookworm AS builder
WORKDIR /src
COPY Cargo.toml Cargo.lock ./
RUN mkdir -p src && echo 'fn main(){}' > src/main.rs \
    && cargo build --release \
    && rm src/main.rs
COPY src ./src
RUN touch src/main.rs \
    && cargo build --release \
    && strip target/release/<name-from-Cargo.toml>

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /src/target/release/<name-from-Cargo.toml> /usr/local/bin/<binary>
ENTRYPOINT ["/usr/local/bin/<binary>"]
```
> `touch src/main.rs` before second `cargo build` is required to invalidate the dummy binary cache.
> The binary name in `strip` and `COPY` must exactly match `name` in `Cargo.toml`.

### Zig
```dockerfile
FROM debian:bookworm-slim AS builder
ARG TARGETARCH
RUN ZIG_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo "aarch64" || echo "x86_64") \
    && wget -q https://ziglang.org/download/0.15.2/zig-${ZIG_ARCH}-linux-0.15.2.tar.xz \
    && tar -xf zig-${ZIG_ARCH}-linux-0.15.2.tar.xz \
    && mv zig-${ZIG_ARCH}-linux-0.15.2 /usr/local/zig
```
> Docker Desktop on Mac = linux/arm64 → must use `aarch64`.

## Known Bugs & Gotchas

| Language | Bug | Fix |
|----------|-----|-----|
| **Rust** | `Duration::as_secs()` truncates sub-second → value = 0 | Use `as_millis() / 1000` or integer ms constants |
| **Go** | `time.Duration.Seconds()` float → int truncation for < 1s | Use integer ms arithmetic |
| **Zig** | `std.debug.print` writes to stderr, not stdout | Benchmark scripts must use `2>&1` |
| **Zig** | Loop buffer shift may overlap memory | Use `std.mem.copyForwards` |
| **Zig** | `build.zig.zon` `.name` must be bare identifier | `.name = .my_project` not `"my-project"` |
| **Rust** | `:8080` fails to parse as SocketAddr | Use `0.0.0.0:8080` |
| **Go CGO + bookworm arm64** | `*C.SwsContext` field fails to resolve | Use Alpine or C helper wrapper |
| **Rust** | `reqwest` default uses native-tls → needs `libssl3` at runtime | Use `features = ["rustls-tls"], default-features = false` |
| **Go** | `http.Response.Body` not drained before close → port exhaustion | `io.Copy(io.Discard, resp.Body)` before `resp.Body.Close()` |
| **Go** | `http.Client` without `Transport` config → connection pool inactive | Add `Transport: &http.Transport{MaxIdleConnsPerHost: 100}` |
| **Zig 0.15** | `std.ArrayList` is unmanaged → `.init(allocator)` removed | Use `.{}` and pass allocator in every method call |
| **Zig 0.15** | `std.time.sleep` removed | Use `std.Thread.sleep` |
| **Zig** | Freeing a string literal → crash | Every heap field must use `allocator.dupe`, including fallback literals |
| **Zig** | `ArrayList.writer()` requires allocator in 0.15 | `buf.writer(allocator)` not `buf.writer()` |
| **Zig** | `std.time.Timer.read()` requires `*Timer` (mutable) | Declare as `var timer = try std.time.Timer.start()` not `const` |
| **Zig** | `std.json.parseFromSlice` with `defer .deinit()` in loop | High allocation overhead per line — avoid for hot-path parsing; use streaming or manual parse instead |

## Language-Specific Rules

### Go
- `unset GOROOT` before every local build
- HTTP client must be shared per worker — never create per request
- Response body: always `io.Copy(io.Discard, resp.Body); resp.Body.Close()`
- Error wrapping: `fmt.Errorf("context: %w", err)`
- `parseArgs()` must match `CMD` positional args in Dockerfile exactly

### Rust
- Builder image: `rust:1.85-bookworm`
- FFmpeg crate: `ffmpeg-sys-next = "8.0"` (not `ffmpeg-next`)
- `reqwest` must always use `rustls-tls` feature
- No `OnceLock` hack for config — pass via state
- No HTTP client in `Stats` struct — use separate `AppState`
- Boolean CLI flags: `#[arg(long, action = ArgAction::SetTrue)]`

### Zig
- Version: **0.15** with `createModule()` + `root_module` in `build.zig`
- Link C libraries without `lib` prefix: `exe.linkSystemLibrary("avformat")`
- Always `exe.linkLibC()` when linking C libraries
- Pass allocator as parameter; never store allocator in structs
- `@constCast` to fix const qualifier; `@ptrCast` for type-unsafe casts
- Zap (HTTP framework): use v0.11 for Zig 0.15+; copies `libfacil.io.so` to `/usr/local/lib/`

## Adding a New Project

1. Create directory structure: `go/`, `rust/`, `zig/`, `test-data/`, `benchmark/run.sh`, `README.md`
2. Add Docker image name row to the table in `.claude/rules/project-rules.md`
3. `benchmark/run.sh` must be Docker-based with auto-save to `benchmark/results/`
4. All 3 languages must emit identical statistics format
5. `README.md` must include: purpose, directory tree, dependencies, build commands, benchmark results table, and key insight
6. Update `PLAN.md` with results after benchmarking

## Planning Workflow (สำหรับ project ขนาดใหญ่)

สำหรับ project ที่มีหลาย epic หรือต้องการ design review ก่อน implement ให้ทำตาม **WORKFLOW.md**:

```
project/
├── .prompts/init.md        ← requirements (schema, tech stack, use cases)
└── .breakdown/
    ├── STATUS.md           ← kanban board (update ทุกครั้งที่ task เปลี่ยน status)
    └── task-X.X-name.md   ← task cards พร้อม acceptance criteria + dependencies
```

กฎ: แต่ละ task ต้องมี unit test และ status [DONE] ได้ก็ต่อเมื่อ test ผ่านแล้วเท่านั้น

## Rules File Structure

ไฟล์ใน `.claude/rules/` มีหน้าที่แยกกัน — ไม่ duplicate กัน:
- **CLAUDE.md** — master reference: build, benchmark, Dockerfile templates, Known Bugs, statistics format, language-specific rules
- **project-rules.md** — checklist ใหม่ทุก project + Docker image naming table
- **project-structure.md** — code patterns ที่ใช้ซ้ำ (Stats struct, helper functions, constants)
- **go-dev.md / rust-dev.md / zig-dev.md** — language-specific deep rules
