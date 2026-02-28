# Task 3.1–3.4: Profile B — Zig (zap v0.11 / facil.io)

## Status
[DONE]

## Priority
— (build task)

## Description
Implement WebSocket public chat server ใน Zig ด้วย `zap` v0.11 (facil.io binding สำหรับ Zig 0.15) — ใช้ pub/sub channel ของ facil.io สำหรับ broadcast, thread-per-connection model เนื่องจาก Zig 0.15 ไม่มี async/await

---

## Task 3.1: Verify Zig WS Library + PoC

### Acceptance Criteria
- [x] ตรวจสอบว่า `zap` v0.11 มี WebSocket support
- [x] PoC: minimal echo server → `wscat -c ws://localhost:8080` echo กลับ ไม่ error
- [x] อัปเดต STATUS.md ด้วย approach ที่เลือก

### Tests Required
- [x] PoC: connect → echo → ไม่ crash

### Dependencies
- Task 0.4 (Zig WS library decision)

---

## Task 3.2: WS Server Core — Connect, Join, Broadcast

### Acceptance Criteria
- [x] TCP listener บน port 8080 ผ่าน zap/facil.io
- [x] HTTP upgrade via zap WebSocket handler
- [x] `clients` array: list ของ active connections
- [x] `join` → เพิ่ม client + บันทึก user string
- [x] `chat` → broadcast ไปทุก client ยกเว้นผู้ส่ง
- [x] connection ปิด → ลบออกจาก list

### Tests Required
- [x] `testBroadcast`: 3 mock clients → ส่งจาก 1, 2+3 ได้รับ
- [x] `testClientCleanup`: close → ลบออก

---

## Task 3.3: Ping/Pong + Rate Limit

### Acceptance Criteria
- [x] Server ส่ง `ping` ทุก 30s
- [x] ไม่รับ `pong` → ปิด connection
- [x] Token bucket per client: `tokens: u32`, refill check ตอน receive
- [x] `std.time.Instant` สำหรับวัดเวลาระหว่าง refill

### Tests Required
- [x] `test_ping_timeout`: mock ที่ไม่ตอบ pong → connection ถูกปิด
- [x] `test_rate_limit`: ส่ง 20 msgs เร็วๆ → 10 ผ่าน, 10 drop

---

## Task 3.4: Stats + Docker

### Acceptance Criteria
- [x] `Stats` struct: `avgLatencyMs()`, `throughput()`, `printStats()`
- [x] Output → stderr (`std.debug.print`)
- [x] CLI args ด้วย `std.process.args()`: positional `port` และ `duration`
- [x] Dockerfile: `debian:bookworm-slim` + zig 0.15.2, `ReleaseFast`
- [x] Smoke test: container start → listen port → ไม่ crash

### Tests Required
- [x] `test_stats_format`: ตรวจ format ของ `printStats()` output

---

## Dependencies
- Task 0.1 (skeleton), Task 0.2 (protocol), Task 0.4 (Zig WS decision)
- Chain: 3.1 → 3.2 → 3.3 → 3.4

## Files Affected
```
profile-b/zig/
├── src/main.zig       # orchestration + arg parsing
├── src/server.zig     # TCP + WS handler
├── src/hub.zig        # client list + broadcast
├── src/protocol.zig   # message parsing (จาก 0.2)
├── src/stats.zig      # Stats struct
├── build.zig
└── Dockerfile
```

## Implementation Notes

### Architecture
- **Thread-per-connection**: Zig 0.15 ไม่มี async/await → ใช้ `std.Thread.spawn`
- **Shared state**: `std.Thread.Mutex` + array of connections
- **Broadcast**: facil.io pub/sub channels (zap wraps นี้ให้)

### Zig-Specific Notes
- `std.mem.copyForwards` สำหรับ buffer operations
- `@constCast` ถ้า C library ต้องการ non-const pointer
- `build.zig.zon` ต้องมี `.fingerprint` field สำหรับ Zig 0.15
- `ReleaseFast` optimization level สำหรับ benchmark

### Manual WS Handshake (ถ้าจำเป็น — ไม่ได้ใช้เพราะ zap รองรับ)
```zig
const WS_MAGIC = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
// 1. parse "Sec-WebSocket-Key" header
// 2. concat key + WS_MAGIC → SHA-1 → base64
// 3. respond 101 Switching Protocols
// 4. framing: 2-byte header + payload
```
