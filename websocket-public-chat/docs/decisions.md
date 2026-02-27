# Architecture Decision Records (ADR)

> สร้างเมื่อ: 2026-02-27 (Task 0.4)

---

## ADR-1: Zig WebSocket Library

**Status**: Accepted

**Question**: zap v0.11 (Zig 0.15) รองรับ WebSocket หรือไม่?

**Research**:
- zap v0.11.0 (Aug 2025) รองรับ Zig 0.15.1 และมี WebSocket support ผ่าน facil.io
- มี `examples/websockets/` — chat app ที่ใช้ channel-based pub/sub
- API: `on_upgrade()` → `on_open_websocket()` → `handle_websocket_message()` → `on_close_websocket()`
- Broadcast ผ่าน `WebsocketHandler.publish(channel, message)`
- Commit: `66c5dc42c781bbb8a9100afda3c7e69ee96eddf3`

**Decision**: ใช้ **zap v0.11.0** สำหรับ Zig WebSocket server

**เพิ่ม dependency ใน build.zig.zon**:
```zig
.dependencies = .{
    .zap = .{
        .url = "git+https://github.com/zigzap/zap#v0.11.0",
        .hash = "...", // ได้จาก zig fetch
    },
},
```

**Alternatives rejected**:
- Manual WS handshake: งานมาก, เสี่ยง bug ใน frame parser
- ws.zig / zig-websocket: ไม่ active, Zig 0.15 compatibility ไม่แน่

---

## ADR-2: Docker Network สำหรับ k6 ↔ Server

**Status**: Accepted

**Decision**: ใช้ Docker user-defined **bridge network** ชื่อ `ws-bench-net`

```bash
docker network create ws-bench-net

# รัน server
docker run -d --rm --network ws-bench-net --name wsc-server <image> --port 8080

# รัน k6
docker run --rm --network ws-bench-net \
  -v "$K6_DIR":/scripts:ro \
  grafana/k6 run -e WS_URL=ws://wsc-server:8080/ws /scripts/steady.js
```

**ข้อดี**:
- k6 ใช้ container name เป็น hostname ได้ (`wsc-server`)
- network isolated ไม่กระทบ host
- ใช้ซ้ำข้ามทุก language ได้ — เพียงเปลี่ยน image name

---

## ADR-3: k6 Output Parsing ใน bash

**Status**: Accepted

**Decision**: parse k6 stdout ด้วย `grep` + `awk` (consistent กับ projects เดิมในรีโป)

```bash
OUTPUT=$(docker run --rm --network ws-bench-net \
  -v "$K6_DIR":/scripts:ro \
  grafana/k6 run -e WS_URL=ws://wsc-server:8080/ws /scripts/steady.js 2>&1)

# Extract metrics
CHECKS=$(echo "$OUTPUT"    | grep "checks_succeeded" | awk '{print $2}')
P95_MS=$(echo "$OUTPUT"    | grep "ws_session_duration" | grep "p(95)" | awk -F'p.95.=' '{print $2}' | awk '{print $1}')
MSGS_SENT=$(echo "$OUTPUT" | grep "chat_msgs_sent\.\.\." | awk -F': ' '{print $2}' | awk '{print $1}')
WS_ERRORS=$(echo "$OUTPUT" | grep "ws_errors\.\.\." | awk -F': ' '{print $2}' | awk '{print $1}')
SESSIONS=$(echo "$OUTPUT"  | grep "ws_sessions\.\.\." | awk -F': ' '{print $2}' | awk '{print $1}')
```

**Output format สำหรับ benchmark/results/**:
```
--- Statistics ---
Scenario: steady
WS Sessions: <N>
Messages Sent: <N>
WS Errors: <N>
p95 Session Duration: <X>ms
Checks: <X>%
```

---

## ADR-4: Rate Limit Implementation

**Status**: Accepted

**Decision**: **Token Bucket** — 1 bucket per connection, capacity=10, refill 10 tokens/sec

**Interface ที่ทุกภาษาต้องทำ**:

```
RateLimiter
  - tokens: int          # current tokens (0-10)
  - last_refill: Instant # timestamp of last refill
  - max: int = 10
  - refill_per_sec: int = 10

  fn allow() bool:
    refill tokens based on elapsed time
    if tokens > 0: tokens -= 1; return true
    else: return false   # drop message, do NOT disconnect
```

**Go**:
```go
type RateLimiter struct {
    tokens    int
    lastCheck time.Time
    mu        sync.Mutex
}
func (r *RateLimiter) Allow() bool { ... }
```

**Rust**:
```rust
struct RateLimiter {
    tokens: u32,
    last_refill: Instant,
}
impl RateLimiter {
    fn allow(&mut self) -> bool { ... }
}
```

**Zig**:
```zig
const RateLimiter = struct {
    tokens: u32,
    last_refill: std.time.Instant,
    fn allow(self: *RateLimiter) bool { ... }
};
```

**กฎ**: rate limit exceeded → drop message เงียบๆ ไม่ disconnect, ไม่ส่ง error กลับ
