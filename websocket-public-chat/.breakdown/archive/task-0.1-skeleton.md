# Task 0.1: Project Skeleton + Dockerfile Templates

## Status
[DONE]

## Priority
— (build task)

## Description
สร้างโครงสร้างไดเรกทอรีและ boilerplate สำหรับทั้ง 3 ภาษา (Go, Rust, Zig) รวมถึง Dockerfile ที่ compile ได้แต่ยังไม่มี logic — เป็น foundation ที่ทุก epic ต่อยอด

## Acceptance Criteria
- [x] โครงสร้าง `profile-b/{go,rust,zig}/` ตาม `.prompts/init.md`
- [x] `go/go.mod` + dependency: `gorilla/websocket v1.5.3`
- [x] `rust/Cargo.toml` + dependency: `tokio`, `tokio-tungstenite 0.24`, `serde_json 1`
- [x] `zig/build.zig` ใช้ Zig 0.15 module syntax (`createModule` + `root_module`)
- [x] Dockerfile ทั้ง 3 ภาษา build ผ่าน produce binary ว่าง
- [x] `k6/` directory พร้อม placeholder scripts
- [x] `benchmark/results/` directory พร้อม `.gitkeep`

## Tests Required
- `docker build` ทั้ง 3 ภาษาผ่าน (smoke test)
- `docker run --rm <image>` exit 0 ไม่ panic

## Dependencies
- ไม่มี (task แรกของ project)

## Files Affected
```
websocket-public-chat/
├── profile-b/go/main.go, go.mod, Dockerfile
├── profile-b/rust/src/main.rs, Cargo.toml, Dockerfile
├── profile-b/zig/src/main.zig, build.zig, Dockerfile
├── k6/{steady,burst,churn}.js          # placeholder
├── benchmark/results/.gitkeep
└── benchmark/run.sh                    # placeholder
```

## Implementation Notes
- Go Dockerfile: `CGO_ENABLED=0`, multi-stage, `bookworm`
- Rust Dockerfile: `rust:1.85-bookworm`, dependency cache layer ก่อน copy source
- Zig Dockerfile: `debian:bookworm-slim` + wget `zig-aarch64-linux-0.15.2`
- ทุก Dockerfile ใช้ multi-stage build เพื่อลด image size
