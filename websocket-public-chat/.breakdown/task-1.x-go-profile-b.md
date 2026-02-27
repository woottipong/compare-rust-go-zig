# Task 1.1–1.3: Profile B — Go (net/http + gorilla/websocket)

## Status
[DONE]

---

## Task 1.1: WS Server Core — Connect, Join, Broadcast

### Acceptance Criteria
- [x] HTTP endpoint `GET /ws` → upgrade เป็น WebSocket
- [x] `Hub` struct: map ของ client connections (thread-safe ด้วย `sync.RWMutex`)
- [x] เมื่อ client connect → ลงทะเบียนใน Hub
- [x] เมื่อรับ `join` → บันทึก user mapping
- [x] เมื่อรับ `chat` → broadcast ไปยัง client อื่นทุกคน (ไม่รวมผู้ส่ง)
- [x] เมื่อรับ `leave` หรือ connection error → unregister ออกจาก Hub

### Tests Required
- [x] `TestBroadcastToOthers`: 3 mock clients, ส่ง chat จาก client 1 → client 2 และ 3 ได้รับ, client 1 ไม่ได้รับ
- [x] `TestHubRegisterUnregister`: register 5 clients, unregister 2 → Hub มี 3 clients

---

## Task 1.2: Ping/Pong Keepalive + Per-Client Rate Limit

### Acceptance Criteria
- [x] Server ส่ง `ping` ทุก 30 วินาที ต่อ connection
- [x] ถ้า client ไม่ตอบ `pong` ภายใน 30 วินาที → `conn.Close()`
- [x] ทุก connection มี token bucket: refill 10 tokens/sec
- [x] เมื่อรับ `chat` แล้วไม่มี token → drop message (log ว่า dropped, ไม่ disconnect)
- [x] ใช้ `time.Ticker` สำหรับทั้ง ping interval และ rate limit refill

### Tests Required
- [x] `TestPingTimeout`: client ไม่ตอบ pong → connection ถูกปิดภายใน 35 วินาที
- [x] `TestRateLimit`: ส่ง 20 messages ใน 1 วินาที → รับผ่านไปแค่ 10, drop 10

---

## Task 1.3: Stats Struct + Docker + Unit Tests

### Acceptance Criteria
- [x] `Stats` struct แยกออกจาก Hub: `totalMessages`, `droppedMessages`, `processingStart`, `connections`
- [x] method: `avgLatencyMs()`, `throughput()`, `printStats()`
- [x] output format ตามมาตรฐาน repo:
  ```
  --- Statistics ---
  Total messages: <N>
  Processing time: <X.XXX>s
  Average latency: <X.XXX>ms
  Throughput: <X.XX> messages/sec
  P95 latency: <X.XXX>ms
  P99 latency: <X.XXX>ms
  Connection success rate: <X.XX>%
  Message drop rate: <X.XX>%
  ```
- [x] CLI args: `./server --port 8080 --duration 60`
- [x] Dockerfile build ผ่าน + smoke test: server start ฟัง port 8080, ไม่ panic
- [x] `go test ./...` ผ่านทั้งหมด

### Tests Required
- [x] `TestStatsOutput`: format ตรงกับมาตรฐาน (ใช้ regexp หรือ string match)
- [x] integration test: server start → k6 steady 5s → stats ออกมาถูกต้อง

## Dependencies
- Task 0.1 (skeleton)
- Task 0.2 (protocol)

## Files Affected
```
go/main.go        # orchestration: parse args → start hub → serve → print stats
go/hub.go         # Hub struct + broadcast logic
go/client.go      # Client struct + read/write pumps
go/protocol.go    # Message types (จาก task 0.2)
go/stats.go       # Stats struct
go/hub_test.go
go/client_test.go
go/stats_test.go
go/Dockerfile
```

## Architecture Notes

```go
// main goroutine: start Hub, serve HTTP, wait duration, print stats
// Hub goroutine: listen register/unregister/broadcast channels
// Client: 2 goroutines each (readPump, writePump) — gorilla WS pattern
// Rate limit: token counter per Client, refilled by ticker in writePump

type Hub struct {
    clients    map[*Client]bool
    broadcast  chan []byte
    register   chan *Client
    unregister chan *Client
    mu         sync.RWMutex
}

type Client struct {
    hub       *Hub
    conn      *websocket.Conn
    send      chan []byte
    user      string
    tokens    int
    lastRefill time.Time
}
```

## Gotchas
- **gorilla/websocket**: ต้องใช้ write pump goroutine แยก — ห้าม write จาก multiple goroutines
- **Hub channel**: ใช้ buffered channel `make(chan []byte, 256)` เพื่อไม่ block ผู้ส่ง
- **Graceful shutdown**: `http.Server.Shutdown(ctx)` + ปิด Hub channel เมื่อ duration หมด
