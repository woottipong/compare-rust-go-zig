# Task 0.1: Project Skeleton + Dockerfile Templates

## Status
[DONE]

## Description
สร้างโครงสร้างไดเรกทอรีและ boilerplate สำหรับทั้ง 3 ภาษา รวมถึง Dockerfile ที่ compile ได้แต่ยังไม่มี logic

## Acceptance Criteria
- [x] โครงสร้างไดเรกทอรีตามที่กำหนดใน `.prompts/init.md`
- [x] `go/go.mod` พร้อม dependency: `gorilla/websocket`
- [x] `rust/Cargo.toml` พร้อม dependency: `tokio`, `tokio-tungstenite`, `serde_json`
- [x] `zig/build.zig` ใช้ Zig 0.15 module syntax (`createModule` + `root_module`)
- [x] Dockerfile ทั้ง 3 ภาษา build ผ่านและ produce binary ว่าง (main() เปล่า)
- [x] `k6/` directory พร้อม placeholder scripts
- [x] `benchmark/results/` directory พร้อม `.gitkeep`

## Tests Required
- `docker build` ทั้ง 3 ภาษาผ่าน (automated ใน CI ได้)
- `docker run --rm <image> --help` หรือ exit 0 (smoke test)

## Dependencies
- ไม่มี (task แรก)

## Files Affected
```
websocket-public-chat/
├── go/main.go                 # func main() { }
├── go/go.mod
├── go/Dockerfile
├── rust/src/main.rs           # fn main() { }
├── rust/Cargo.toml
├── rust/Cargo.lock
├── rust/Dockerfile
├── zig/src/main.zig           # pub fn main() !void { }
├── zig/build.zig
├── zig/Dockerfile
├── k6/steady.js               # placeholder
├── k6/burst.js                # placeholder
├── k6/churn.js                # placeholder
├── benchmark/results/.gitkeep
└── benchmark/run.sh           # placeholder
```

## Notes
- Go Dockerfile: CGO_ENABLED=0, multi-stage, bookworm
- Rust Dockerfile: `rust:1.85-bookworm`, dependency cache layer ก่อน copy source
- Zig Dockerfile: `debian:bookworm-slim` + wget zig-aarch64-linux-0.15.2
- `gorilla/websocket` version: `v1.5.3` (latest stable)
- Rust `tokio-tungstenite`: `0.24` + `serde_json`: `1`
