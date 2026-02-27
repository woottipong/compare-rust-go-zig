# Project: WebSocket Public Chat Benchmark

เปรียบเทียบ Go / Rust / Zig ในงาน real-time WebSocket broadcast ทั้ง 2 profile:
- **Profile B (Primary)** — Minimal/Low-level: ลด framework abstraction ให้มากที่สุด
- **Profile A (Secondary)** — Framework: ใช้ production-grade framework ต่อ profile เดียวกัน

---

## Tech Stack

### Profile B — Minimal (Primary)
| ภาษา | Server | Notes |
|------|--------|-------|
| Go | `net/http` + `gorilla/websocket` | connection pool แบบ manual |
| Rust | `tokio` + `tokio-tungstenite` | ไม่ใช้ Axum/Actix |
| Zig | `std.net` + `zap` v0.11 (Zig 0.15) | หรือ manual WS handshake ถ้า zap ไม่รองรับ WS |

### Profile A — Framework (Secondary)
| ภาษา | Server | Notes |
|------|--------|-------|
| Go | `GoFiber` + fiber websocket | |
| Rust | `Axum` + `tokio-tungstenite` | |
| Zig | `zap` framework | ถ้ารองรับ WS, ไม่งั้น fallback Profile B |

### Load Tester
- **k6** (JavaScript) — รองรับ WebSocket natively
- ทำงานใน Docker container แยก

---

## Message Protocol (JSON)

### Message Schema
```json
{ "type": "join",  "room": "public",  "user": "client-42" }
{ "type": "chat",  "user": "client-42", "text": "hello world (padded to 128 bytes...)" }
{ "type": "ping",  "ts": 1700000000000 }
{ "type": "pong",  "ts": 1700000000000 }
{ "type": "leave", "user": "client-42" }
```

### Payload Size
- `chat` message: **128 bytes** (padded ถ้าสั้นกว่า) — เท่ากันทุกภาษา
- `join` / `leave` / `ping` / `pong`: ตามจริง (เล็ก)

### Server Behavior
- เมื่อรับ `join` → ลงทะเบียน client ในห้อง
- เมื่อรับ `chat` → broadcast ให้ client อื่นทุกคนในห้อง (ไม่รวมผู้ส่ง)
- เมื่อรับ `ping` → ตอบ `pong` พร้อม ts เดิม
- เมื่อรับ `leave` / connection ปิด → ลบ client ออกจากห้อง
- Ping/Pong keepalive: **30 วินาที** (server-initiated) → kick ถ้าไม่ตอบ
- Per-client rate limit: **10 msg/sec** → drop message ถ้าเกิน (ไม่ disconnect)

---

## Use Cases

1. Client เชื่อมต่อ WebSocket → ส่ง `join` → รับ broadcast จาก client อื่น
2. Client ส่ง `chat` → server broadcast ไปยัง client อื่นทุกคนในห้องเดียวกัน
3. Client ส่ง `ping` → server ตอบ `pong` (latency measurement)
4. Server ตัด connection ที่ไม่ active เกิน 30 วินาที
5. Client ส่งเกิน 10 msg/sec → server drop ส่วนเกิน (no disconnect)
6. Client ส่ง `leave` หรือ disconnect → ออกจากห้อง

---

## Non-goals (v1)

- JWT / Authentication / Authorization
- Message history / persistence
- Multiple rooms (single room "public" เท่านั้น)
- File / image transfer
- Multi-region / distributed state
- TLS (plain WS ws:// สำหรับ benchmark environment)

---

## Benchmark Scenarios

### Scenario 1: Steady Load
```
100 clients เชื่อมต่อพร้อมกัน
แต่ละ client ส่ง 1 chat/sec
duration: 60 วินาที (ลดจาก 5 นาทีเพื่อ benchmark)
วัด: throughput (msg/sec), latency avg/p95/p99
```

### Scenario 2: Burst Connect
```
1000 clients เชื่อมต่อภายใน 10 วินาที
ทุก client ส่ง join แล้วรอ 5 วินาที แล้ว leave
วัด: connection success rate, peak memory
```

### Scenario 3: Churn
```
200 clients constant active
ทุก 2 วินาที: 10 clients disconnect + 10 clients ใหม่ connect
duration: 60 วินาที
วัด: reconnect overhead, message drop rate
```

---

## Statistics Output (มาตรฐาน repo)

```
--- Statistics ---
Total messages: <N>
Processing time: <X.XXX>s
Average latency: <X.XXX>ms
Throughput: <X.XX> messages/sec
```

เพิ่มเติมสำหรับโปรเจกต์นี้:
```
P95 latency: <X.XXX>ms
P99 latency: <X.XXX>ms
Connection success rate: <X.XX>%
Message drop rate: <X.XX>%
```

---

## Success Metrics

- Throughput >= 10,000 msg/sec (burst phase)
- P95 latency < 50ms (steady phase)
- Memory < 100MB สำหรับ 1000 active connections
- Connection success rate > 99%
- Message drop rate < 1%

---

## Project Structure

```
websocket-public-chat/
├── profile-b/                    # Profile B (minimal) — benchmarked ✅
│   ├── go/                       # net/http + gorilla/websocket  → image: wsc-go
│   │   ├── main.go
│   │   ├── hub.go
│   │   ├── client.go
│   │   ├── stats.go
│   │   ├── protocol.go
│   │   ├── go.mod
│   │   └── Dockerfile
│   ├── rust/                     # tokio + tokio-tungstenite     → image: wsc-rust
│   │   ├── src/{main,hub,client,stats,protocol}.rs
│   │   ├── Cargo.toml
│   │   └── Dockerfile
│   └── zig/                      # zap v0.11 (facil.io)          → image: wsc-zig
│       ├── src/{main,server,hub,stats,protocol}.zig
│       ├── build.zig
│       └── Dockerfile
├── profile-a/                    # Profile A (framework) — Epic 5
│   ├── go/                       # GoFiber v2 + gofiber/websocket/v2  → image: wsca-go
│   ├── rust/                     # Axum 0.7 + axum::extract::ws       → image: wsca-rust
│   └── zig/                      # zap v0.11 (copy — same framework)  → image: wsca-zig
├── k6/
│   ├── steady.js                 # Scenario 1
│   ├── burst.js                  # Scenario 2
│   ├── churn.js                  # Scenario 3
│   └── Dockerfile
├── benchmark/
│   ├── run.sh                    # wrapper → run-profile-b.sh
│   ├── run-profile-b.sh          # รัน Profile B (wsc-*)
│   ├── run-profile-a.sh          # รัน Profile A (wsca-*)
│   └── results/
└── README.md
```

---

## Open Questions (ต้อง resolve ก่อน implement)

1. **Zig WebSocket**: `zap` v0.11 รองรับ WS หรือไม่? → ถ้าไม่ ต้องใช้ manual WS frame parsing หรือหา library อื่น
2. **k6 Docker**: ใช้ `grafana/k6` image หรือ build เอง?
3. **Docker network**: ใช้ Docker network เพื่อให้ k6 container คุยกับ server container
4. **Port**: server ฟัง `:8080`, k6 เชื่อม `ws://server:8080/ws`
5. **Rate limit implementation**: ใช้ token bucket per connection (in-memory) — ไม่ใช้ Redis
