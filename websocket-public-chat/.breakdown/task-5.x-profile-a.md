# Task 5.1–5.4: Profile A — Framework Servers (Secondary)

## Status
[TODO] — เริ่มได้หลัง Epic 4 เสร็จ (benchmark harness พร้อมแล้ว)

---

## Overview

Profile A ใช้ framework เพื่อดู delta เทียบกับ Profile B:
- **เป้าหมาย**: วัดว่า framework abstraction เพิ่มหรือลด throughput/latency เท่าไหร่
- **Protocol**: ใช้ k6 scripts เดิมทุกตัว (ไม่เปลี่ยน)
- **Directory**: `profile-a/go/`, `profile-a/rust/`, `profile-a/zig/`

---

## Task 5.1: Profile A — Go (GoFiber + websocket)

### Acceptance Criteria
- [ ] `github.com/gofiber/fiber/v2` + `github.com/gofiber/websocket/v2`
- [ ] endpoint `/ws` upgrade ด้วย Fiber middleware
- [ ] Hub + broadcast logic เหมือน Profile B (copy, ไม่แชร์ code)
- [ ] Rate limit + ping/pong เหมือนกัน
- [ ] Stats output format เหมือนกัน
- [ ] Dockerfile แยก (profile-a/go/Dockerfile)

### Tests Required
- [ ] รัน k6/steady.js กับ Profile A Go server — ผ่านโดยไม่ error
- [ ] `go test ./profile-a/go/...` ผ่าน

---

## Task 5.2: Profile A — Rust (Axum + tokio-tungstenite)

### Acceptance Criteria
- [ ] `axum` + `axum::extract::ws::WebSocket`
- [ ] handler: `async fn ws_handler(ws: WebSocketUpgrade, ...) -> impl IntoResponse`
- [ ] AppState, broadcast, rate limit, ping/pong — เหมือน Profile B
- [ ] Dockerfile แยก

### Tests Required
- [ ] รัน k6/steady.js กับ Profile A Rust server — ผ่าน
- [ ] `cargo test --manifest-path profile-a/rust/Cargo.toml` ผ่าน

---

## Task 5.3: Profile A — Zig (zap framework)

### Acceptance Criteria
- [ ] ใช้ `zap` v0.11 สำหรับ HTTP + WS (ถ้ารองรับจาก task 0.4)
- [ ] ถ้า zap ไม่รองรับ WS → task นี้ใช้ implementation เดิมจาก Profile B (ข้ามไป)
- [ ] Dockerfile แยก

### Tests Required
- [ ] รัน k6/steady.js กับ Profile A Zig server — ผ่าน

---

## Task 5.4: Profile B vs A Comparison + benchmark/run-profile-a.sh

### Acceptance Criteria
- [ ] `benchmark/run-profile-a.sh`: รัน 3 scenarios × 3 ภาษา เหมือน `run.sh`
- [ ] Results table ใน README เปรียบเทียบ Profile B vs A:

```
| Language | Profile | Throughput | P95 Latency | Memory/conn |
|----------|---------|-----------|-------------|-------------|
| Go       | B (minimal) | X msg/s | Xms | XKB |
| Go       | A (fiber)   | X msg/s | Xms | XKB |
| Rust     | B (minimal) | X msg/s | Xms | XKB |
| Rust     | A (axum)    | X msg/s | Xms | XKB |
| Zig      | B (minimal) | X msg/s | Xms | XKB |
| Zig      | A (zap)     | X msg/s | Xms | XKB |
```

- [ ] Key insight: "framework ทำให้ latency เพิ่ม/ลด X% เพราะอะไร"
- [ ] Auto-save results ใน `benchmark/results/profile-a_<timestamp>.txt`

## Dependencies
- Task 4.4 (benchmark harness + run.sh สมบูรณ์แล้ว)
- Task 5.1, 5.2, 5.3

## Files Affected
```
profile-a/
├── go/
│   ├── main.go
│   ├── go.mod
│   └── Dockerfile
├── rust/
│   ├── src/main.rs
│   ├── Cargo.toml
│   └── Dockerfile
└── zig/
    ├── src/main.zig
    ├── build.zig
    └── Dockerfile
benchmark/run-profile-a.sh
README.md   # เพิ่ม Profile A section
```

## Notes
- **Code duplication**: copy-paste จาก Profile B เป็นเรื่องปกติ — อย่า abstract ร่วมกัน เพราะจะ complicate Dockerfile
- **Framework versions**: Go GoFiber v2 latest, Rust Axum 0.7, Zig zap v0.11
- **Expected outcome**: Framework เพิ่ม developer ergonomics แต่อาจ +5-20% latency จาก middleware layers
