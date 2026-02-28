# Task 2.1–2.3: Profile B — Rust (tokio + tokio-tungstenite)

## Status
[DONE]

## Priority
— (build task)

## Description
Implement WebSocket public chat server ใน Rust ด้วย minimal async stack (`tokio` + `tokio-tungstenite`) — ไม่ใช้ Axum/Actix เพื่อเทียบ raw async I/O performance กับ Go goroutine model

---

## Task 2.1: WS Server Core — Connect, Join, Broadcast

### Acceptance Criteria
- [x] `tokio::net::TcpListener` bind `:8080`
- [x] แต่ละ connection spawn `tokio::task`
- [x] `AppState`: `Arc<RwLock<HashMap<Uuid, Sender<Message>>>>` สำหรับ broadcast
- [x] `join` → insert sender ลงใน state
- [x] `chat` → iterate state, send ไปทุก client ยกเว้นตัวเอง
- [x] connection drop → remove sender ออกจาก state

### Tests Required
- [x] `test_broadcast_to_others`: 3 mock task channels → ส่งจาก 1, 2+3 ได้รับ
- [x] `test_state_cleanup`: drop connection → entry ถูกลบจาก state

---

## Task 2.2: Ping/Pong Keepalive + Per-Client Rate Limit

### Acceptance Criteria
- [x] Server ส่ง `Message::Ping` ทุก 30s ด้วย `tokio::time::interval`
- [x] ไม่รับ `Message::Pong` ใน 30s → ปิด connection
- [x] Token bucket per connection: `tokens: u32 = 10`, refill ทุก 100ms (+1, max 10)
- [x] `chat` เมื่อ `tokens == 0` → drop (ไม่ส่ง error)

### Tests Required
- [x] `test_ping_timeout`: mock ที่ไม่ตอบ pong → task จบใน ~30s (`tokio::time::pause`)
- [x] `test_rate_limit_drop`: ส่ง 20 msgs เร็วๆ → tokens ลดลงถูกต้อง, drop เมื่อหมด

---

## Task 2.3: Stats Struct + Docker + Unit Tests

### Acceptance Criteria
- [x] `Stats` struct แยกต่างหาก — ส่งผ่าน `Arc<Mutex<Stats>>`
- [x] Output format ตามมาตรฐาน repo
- [x] CLI args ด้วย `clap`: `--port <u16>`, `--duration <u64>`
- [x] Dockerfile: `rust:1.85-bookworm`, dependency cache layer, `strip` binary
- [x] `cargo test` ผ่านทั้งหมด

### Tests Required
- [x] `test_stats_format`: output string ตรง expected format
- [x] Integration test (`tokio::test`): start server → connect → send chat → verify broadcast

---

## Dependencies
- Task 0.1 (skeleton), Task 0.2 (protocol)

## Files Affected
```
profile-b/rust/
├── src/main.rs       # orchestration
├── src/hub.rs        # AppState + broadcast logic
├── src/client.rs     # per-connection handler task
├── src/protocol.rs   # Message types (จาก task 0.2)
├── src/stats.rs      # Stats struct
├── src/tests/        # unit + integration tests
├── Cargo.toml
└── Dockerfile
```

## Implementation Notes

### Architecture
```rust
type Clients = Arc<RwLock<HashMap<Uuid, mpsc::Sender<WsMessage>>>>;

// per-connection task
async fn handle_connection(
    stream: TcpStream,
    clients: Clients,
    stats: Arc<Mutex<Stats>>,
) {
    let ws = tokio_tungstenite::accept_async(stream).await?;
    let (write, read) = ws.split();
    let (tx, rx) = mpsc::channel(64);
    // writePump: forward from channel to WebSocket
    // readPump: handle incoming, broadcast, rate limit
    // keepalive: tokio::time::interval(30s)
}
```

### Gotchas
- **`tokio::sync::RwLock`** ไม่ใช่ `std::sync::RwLock` — ใช้ผิดจะ deadlock ใน async context
- **`split()` ownership**: `SplitSink`/`SplitStream` ต้องจัดการ lifetime อย่างระวัง
- **Stats แยกจาก AppState**: `Arc<Mutex<Stats>>` แยก เพื่อไม่ให้ lock contention กับ broadcast
- **`tokio-tungstenite` ไม่ต้อง TLS**: ไม่ enable `native-tls`/`rustls` features
