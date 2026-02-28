# Task 1.1–1.3: Profile B — Go (net/http + gorilla/websocket)

## Status
[DONE]

## Priority
— (build task)

## Description
Implement WebSocket public chat server ใน Go ด้วย minimal stack (`net/http` + `gorilla/websocket`) — เป็น Profile B (primary) ที่เน้นเทียบ runtime/network behavior โดยลดผลจาก framework abstraction

---

## Task 1.1: WS Server Core — Connect, Join, Broadcast

### Acceptance Criteria
- [x] HTTP endpoint `GET /ws` → upgrade เป็น WebSocket
- [x] `Hub` struct: map ของ client connections (thread-safe ด้วย `sync.RWMutex`)
- [x] `join` → ลงทะเบียน client ใน Hub
- [x] `chat` → broadcast ไปทุก client ยกเว้นผู้ส่ง
- [x] `leave` / connection error → unregister ออกจาก Hub

### Tests Required
- [x] `TestBroadcastToOthers`: 3 mock clients → ส่งจาก 1, client 2+3 ได้รับ, client 1 ไม่ได้รับ
- [x] `TestHubRegisterUnregister`: register 5 → unregister 2 → Hub มี 3 clients

---

## Task 1.2: Ping/Pong Keepalive + Per-Client Rate Limit

### Acceptance Criteria
- [x] Server ส่ง `ping` ทุก 30 วินาทีต่อ connection
- [x] ถ้า client ไม่ตอบ `pong` ใน 30 วินาที → `conn.Close()`
- [x] Token bucket per connection: refill 10 tokens/sec
- [x] `chat` เมื่อ token หมด → drop message (log, ไม่ disconnect)
- [x] ใช้ `time.Ticker` สำหรับ ping interval และ rate limit refill

### Tests Required
- [x] `TestPingTimeout`: ไม่ตอบ pong → connection ถูกปิดภายใน ~35s
- [x] `TestRateLimit`: ส่ง 20 msgs ใน 1s → 10 ผ่าน, 10 drop

---

## Task 1.3: Stats Struct + Docker + Unit Tests

### Acceptance Criteria
- [x] `Stats` struct แยกจาก Hub: `totalMessages`, `droppedMessages`, `processingStart`, `connections`
- [x] Methods: `avgLatencyMs()`, `throughput()`, `printStats()`
- [x] Output format ตามมาตรฐาน repo (Statistics block)
- [x] CLI args: `./server --port 8080 --duration 60`
- [x] Dockerfile build ผ่าน + smoke test
- [x] `go test ./...` ผ่านทั้งหมด

### Tests Required
- [x] `TestStatsOutput`: format ตรงกับมาตรฐาน (regexp match)
- [x] Integration test: server start → k6 steady 5s → stats ถูกต้อง

---

## Dependencies
- Task 0.1 (skeleton), Task 0.2 (protocol)

## Files Affected
```
profile-b/go/
├── main.go         # orchestration: parse args → start hub → serve → print stats
├── hub.go          # Hub struct + broadcast logic
├── client.go       # Client struct + read/write pumps
├── protocol.go     # Message types (จาก task 0.2)
├── stats.go        # Stats struct
├── hub_test.go
├── client_test.go
├── stats_test.go
└── Dockerfile
```

## Implementation Notes

### Architecture
```
main goroutine → start Hub → serve HTTP → wait duration → print stats
Hub goroutine  → listen register/unregister/broadcast channels
Client         → 2 goroutines each (readPump, writePump) — gorilla WS pattern
Rate limit     → token counter per Client, refilled by ticker in writePump
```

### Key Structs
```go
type Hub struct {
    clients    map[*Client]bool
    broadcast  chan []byte
    register   chan *Client
    unregister chan *Client
    mu         sync.RWMutex
}

type Client struct {
    hub        *Hub
    conn       *websocket.Conn
    send       chan []byte    // buffered: 256
    user       string
    tokens     int
    lastRefill time.Time
}
```

### Gotchas
- **gorilla/websocket**: ต้องใช้ write pump goroutine แยก — ห้าม write จาก multiple goroutines
- **Hub channel**: ใช้ buffered `make(chan []byte, 256)` เพื่อไม่ block ผู้ส่ง
- **Graceful shutdown**: `http.Server.Shutdown(ctx)` + ปิด Hub channel เมื่อ duration หมด
