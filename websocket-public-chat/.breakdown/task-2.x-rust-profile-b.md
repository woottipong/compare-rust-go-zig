# Task 2.1–2.3: Profile B — Rust (tokio + tokio-tungstenite)

## Status
[TODO]

---

## Task 2.1: WS Server Core — Connect, Join, Broadcast

### Acceptance Criteria
- [ ] `tokio::net::TcpListener` bind `:8080`
- [ ] แต่ละ connection spawn `tokio::task`
- [ ] `AppState`: `Arc<RwLock<HashMap<Uuid, Sender<Message>>>>` สำหรับ broadcast
- [ ] เมื่อรับ `join` → insert sender ลงใน state
- [ ] เมื่อรับ `chat` → iterate state และ send ไปทุก client ยกเว้นตัวเอง
- [ ] เมื่อ connection drop → remove sender ออกจาก state

### Tests Required
- [ ] `test_broadcast_to_others`: 3 mock task channels, ส่ง chat จาก 1 → 2 และ 3 ได้รับ
- [ ] `test_state_cleanup`: drop connection → entry ถูกลบออกจาก state

---

## Task 2.2: Ping/Pong Keepalive + Per-Client Rate Limit

### Acceptance Criteria
- [ ] Server ส่ง `Message::Ping` ทุก 30 วินาที ด้วย `tokio::time::interval`
- [ ] ถ้าไม่รับ `Message::Pong` ใน 30 วินาที → ปิด connection
- [ ] Token bucket per connection: `tokens: u32 = 10`, refill ทุก 100ms (+1 token, max 10)
- [ ] เมื่อรับ `chat` และ `tokens == 0` → drop (ไม่ส่ง error)

### Tests Required
- [ ] `test_ping_timeout`: mock connection ที่ไม่ตอบ pong → task จบใน ~30s (ทดสอบด้วย `tokio::time::pause`)
- [ ] `test_rate_limit_drop`: ส่ง 20 messages เร็วๆ → `tokens` ลดลงถูกต้อง, drop เมื่อหมด

---

## Task 2.3: Stats Struct + Docker + Unit Tests

### Acceptance Criteria
- [ ] `Stats` struct แยกต่างหาก (ไม่ใช้ `OnceLock` หรือ global) — ส่งผ่าน `Arc<Mutex<Stats>>`
- [ ] output format ตามมาตรฐาน repo
- [ ] CLI args ด้วย `clap`: `--port <u16>`, `--duration <u64>`
  - boolean flag: `#[arg(long, action = ArgAction::SetTrue)]` ถ้ามี
- [ ] Dockerfile: `rust:1.85-bookworm`, dependency cache layer, `strip` binary
- [ ] `cargo test` ผ่านทั้งหมด

### Tests Required
- [ ] `test_stats_format`: ตรวจว่า output string ตรงกับ expected format
- [ ] integration test ด้วย `tokio::test`: start server, connect 1 client, send chat, verify broadcast

## Dependencies
- Task 0.1, 0.2
- Task 2.1

## Files Affected
```
rust/src/main.rs      # orchestration
rust/src/hub.rs       # AppState + broadcast logic
rust/src/client.rs    # per-connection handler task
rust/src/protocol.rs  # Message types (จาก task 0.2)
rust/src/stats.rs     # Stats struct
rust/src/tests/       # unit + integration tests
rust/Cargo.toml
rust/Dockerfile
```

## Architecture Notes

```rust
type Clients = Arc<RwLock<HashMap<Uuid, mpsc::Sender<WsMessage>>>>;

// per-connection task
async fn handle_connection(
    stream: TcpStream,
    clients: Clients,
    stats: Arc<Mutex<Stats>>,
) {
    let ws = tokio_tungstenite::accept_async(stream).await.unwrap();
    let (mut write, mut read) = ws.split();
    let (tx, mut rx) = mpsc::channel(64);
    let id = Uuid::new_v4();

    // writePump: forward from channel to WebSocket
    // readPump: handle incoming messages, broadcast, rate limit
    // keepalive: tokio::time::interval(Duration::from_secs(30))
}
```

## Gotchas
- **`tokio-tungstenite` ไม่ compatible กับ `native-tls`**: ใช้ `features = ["rustls-tls-webpki-roots"]` ถ้าต้องการ TLS (ไม่จำเป็นสำหรับ benchmark)
- **`RwLock` ใน async**: ใช้ `tokio::sync::RwLock` ไม่ใช่ `std::sync::RwLock` (deadlock risk)
- **`split()` ownership**: `SplitSink` / `SplitStream` ต้องจัดการ lifetime อย่างระวัง
- **Stats ไม่อยู่ใน `AppState`**: แยก `Arc<Mutex<Stats>>` ออก เพื่อไม่ให้ lock contention กับ broadcast state
