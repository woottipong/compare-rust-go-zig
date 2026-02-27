# Task 3.1–3.4: Profile B — Zig (std.net / zap)

## Status
[TODO] — blocked on Task 0.4 (Zig WS library decision)

---

## Task 3.1: Verify Zig WS Library + PoC

### Acceptance Criteria
- [ ] ตรวจสอบว่า `zap` v0.11 มี WebSocket support หรือไม่
- [ ] ถ้ามี: เขียน minimal echo server 20 บรรทัด verify ว่า `upgrade` ทำงานได้
- [ ] ถ้าไม่มี: ค้นหา `zig-websocket` หรือ library อื่น — ถ้าไม่มีเลย ทำ manual WS handshake (plan อยู่ด้านล่าง)
- [ ] update `.breakdown/STATUS.md` ด้วย approach ที่เลือก

### Tests Required
- [ ] PoC: connect ด้วย `wscat -c ws://localhost:8080` → echo กลับ → ไม่ error

### Dependencies
- Task 0.4

---

## Task 3.2: WS Server Core — Connect, Join, Broadcast

### Acceptance Criteria (ขึ้นกับ approach จาก 3.1)
- [ ] TCP listener บน port 8080
- [ ] HTTP upgrade handler (ไม่ว่าจะใช้ library หรือ manual)
- [ ] `clients` array (dynamic): list ของ active connections
- [ ] เมื่อรับ `join` → เพิ่ม client เข้า list + บันทึก user string
- [ ] เมื่อรับ `chat` → broadcast ไปทุก client ในลิสต์ยกเว้นผู้ส่ง
- [ ] เมื่อ connection ปิด → ลบออกจาก list

### Tests Required
- [ ] unit test `testBroadcast`: 3 mock clients, ส่งจาก 1 → 2 และ 3 ได้รับ
- [ ] unit test `testClientCleanup`: close → ลบออก

---

## Task 3.3: Ping/Pong + Rate Limit

### Acceptance Criteria
- [ ] Server ส่ง `ping` ทุก 30 วินาที ด้วย `std.Thread.sleep` ใน goroutine แยก
- [ ] ถ้าไม่รับ `pong` → ปิด connection (`conn.close()`)
- [ ] Token bucket per client: `tokens: u32`, refill ใน background thread หรือ check ตอน receive
- [ ] `std.time.Instant` สำหรับวัดเวลาระหว่าง refill

### Tests Required
- [ ] `test_ping_timeout`: mock ที่ไม่ตอบ pong → connection ถูกปิด
- [ ] `test_rate_limit`: ส่ง 20 messages เร็วๆ → 10 ผ่าน, 10 drop

---

## Task 3.4: Stats + Docker

### Acceptance Criteria
- [ ] `Stats` struct ที่มี method: `avgLatencyMs()`, `throughput()`, `printStats()`
- [ ] `std.debug.print` → ไปยัง stderr (benchmark script ใช้ `2>&1`)
- [ ] CLI args ด้วย `std.process.args()`: positional `port` และ `duration`
- [ ] Dockerfile: `debian:bookworm-slim` + zig 0.15.2 aarch64, `ReleaseFast`
- [ ] smoke test: container start → listen port → ไม่ crash

### Tests Required
- [ ] `test_stats_format`: ตรวจ format ของ `printStats()` output

## Dependencies
- Task 0.1, 0.2
- Task 3.1 → 3.2 → 3.3

## Files Affected
```
zig/src/main.zig       # orchestration + arg parsing
zig/src/server.zig     # TCP + WS handler
zig/src/hub.zig        # client list + broadcast
zig/src/protocol.zig   # message parsing (จาก 0.2)
zig/src/stats.zig      # Stats struct
zig/build.zig
zig/Dockerfile
```

## Manual WebSocket Handshake (ถ้าต้องใช้)

ถ้า library ไม่มี WS support ต้อง implement HTTP upgrade เอง:

```zig
// 1. รับ HTTP request จาก TCP stream
// 2. parse "Sec-WebSocket-Key" header
// 3. concat key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
// 4. SHA-1 hash → base64 encode → ส่ง 101 Switching Protocols
// 5. จากนั้น framing: 2-byte header + optional extended length + payload

const WS_MAGIC = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

fn computeAcceptKey(key: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var concat = try std.fmt.allocPrint(allocator, "{s}{s}", .{key, WS_MAGIC});
    defer allocator.free(concat);
    var hash: [std.crypto.hash.Sha1.digest_length]u8 = undefined;
    std.crypto.hash.Sha1.hash(concat, &hash, .{});
    return std.base64.standard.Encoder.encodeAlloc(allocator, &hash);
}
```

## Zig-Specific Notes
- ใช้ `std.Thread.spawn` สำหรับแต่ละ connection (thread-per-connection model)
- Shared state ด้วย `std.Thread.Mutex` + array of connections
- `std.mem.copyForwards` สำหรับ buffer operations
- `@constCast` ถ้า C library ต้องการ non-const pointer
- Zig ไม่มี async/await ใน 0.15 → thread-per-connection เป็น approach ที่ practical ที่สุด
