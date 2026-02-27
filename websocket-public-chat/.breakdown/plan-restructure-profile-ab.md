# Plan: แยก Profile A / Profile B ให้ขาดจากกัน

## โครงสร้างเป้าหมาย

```
websocket-public-chat/
├── profile-b/                  ← ย้ายจาก go/ rust/ zig/ เดิม (ไม่แตะโค้ด)
│   ├── go/                     # net/http + gorilla/websocket
│   ├── rust/                   # tokio + tokio-tungstenite
│   └── zig/                    # zap v0.11
├── profile-a/                  ← ใหม่ทั้งหมด
│   ├── go/                     # GoFiber v2 + gofiber/websocket/v2
│   ├── rust/                   # Axum 0.7 + axum::extract::ws
│   └── zig/                    # copy profile-b/zig/ (zap = framework แล้ว)
├── k6/                         ← ไม่เปลี่ยน
├── benchmark/
│   ├── run.sh                  ← wrapper (ไม่เปลี่ยน)
│   ├── run-profile-b.sh        ← แก้ paths ให้ชี้ profile-b/
│   └── run-profile-a.sh        ← เขียนใหม่ ชี้ profile-a/, images wsca-*
└── README.md                   ← อัปเดต tree + benchmark section
```

---

## Phase 1 — ย้าย Profile B (git mv)

```bash
mkdir -p profile-b
git mv go   profile-b/go
git mv rust profile-b/rust
git mv zig  profile-b/zig
```

**ไม่แตะโค้ดในไฟล์เหล่านี้เลย** — เพียงย้าย directory

### แก้ run-profile-b.sh (2 จุดเท่านั้น)

ปัจจุบัน `build_image` ชี้ `"$PROJECT_DIR/$lang/"` →
แก้เป็น `"$PROJECT_DIR/profile-b/$lang/"`

```bash
# เดิม
docker build -q -t "wsc-${lang}" "$PROJECT_DIR/$lang/" ...

# ใหม่
docker build -q -t "wsc-${lang}" "$PROJECT_DIR/profile-b/$lang/" ...
```

---

## Phase 2 — Profile A Zig (copy เหมือนกัน 100%)

```bash
cp -r profile-b/zig profile-a/zig
```

- Code เหมือนกันทุกตัว
- Docker image tag: **`wsca-zig`** (แยกจาก `wsc-zig`)
- ไม่แก้อะไรในโค้ดเลย — Dockerfile ENTRYPOINT, build.zig, main.zig เหมือนกัน

---

## Phase 3 — Profile A Go (GoFiber + gofiber/websocket/v2)

### ไฟล์ที่ copy ตรงๆ จาก profile-b/go/ (ไม่แก้)

| ไฟล์ | เหตุผล |
|------|--------|
| `hub.go` | Hub/broadcast logic ไม่เกี่ยวกับ HTTP layer |
| `stats.go` | atomic Stats ไม่เปลี่ยน |
| `protocol.go` | Message types ไม่เปลี่ยน |

### ไฟล์ที่เปลี่ยน

**`profile-a/go/main.go`** — แทน `http.NewServeMux` ด้วย Fiber:
```go
app := fiber.New(fiber.Config{ReadTimeout: 10*time.Second})

// WebSocket upgrade middleware
app.Use("/ws", func(c *fiber.Ctx) error {
    if websocket.IsWebSocketUpgrade(c) {
        return c.Next()
    }
    return fiber.ErrUpgradeRequired
})

// WS route
app.Get("/ws", websocket.New(func(c *websocket.Conn) {
    serveWs(hub, c)
}))

// Health
app.Get("/health", func(c *fiber.Ctx) error {
    return c.SendStatus(fiber.StatusOK)
})

// Duration shutdown
if *duration > 0 {
    go func() {
        time.Sleep(time.Duration(*duration) * time.Second)
        app.Shutdown()
    }()
}

log.Printf("websocket-public-chat: listening on :%s", *port)
app.Listen(":" + *port)   // blocks
stats.printStats()
```

**`profile-a/go/client.go`** — เปลี่ยน 3 จุดเท่านั้น:
1. Import: `"github.com/gofiber/websocket/v2"` แทน gorilla
2. ลบ `var upgrader` (Fiber จัดการ upgrade เอง)
3. `serveWs(hub *Hub, c *websocket.Conn)` รับ `*websocket.Conn` โดยตรง — ไม่ต้อง upgrade

> **gofiber/websocket/v2 ใช้ gorilla ข้างใน** — `ReadMessage`, `WriteMessage`,
> `SetPongHandler`, `SetReadDeadline` ทุกอย่าง API เหมือนกัน 100%
> ดังนั้น readPump/writePump/allow() ไม่ต้องเปลี่ยนเลย

**`profile-a/go/go.mod`**:
```
module profile-a-go
go 1.25
require (
    github.com/gofiber/fiber/v2 v2.52.11
    github.com/gofiber/websocket/v2 v2.2.1
)
```

**`profile-a/go/Dockerfile`** — Go non-CGO template จาก CLAUDE.md:
```dockerfile
FROM golang:1.25-bookworm AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN mkdir -p /out && CGO_ENABLED=0 GOOS=linux \
    go build -trimpath -ldflags='-s -w' -o /out/websocket-public-chat .

FROM debian:bookworm-slim
COPY --from=builder /out/websocket-public-chat /usr/local/bin/websocket-public-chat
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/websocket-public-chat"]
```

---

## Phase 4 — Profile A Rust (Axum 0.7 + axum::extract::ws)

### ไฟล์ที่ copy ตรงๆ จาก profile-b/rust/ (ไม่แก้)

| ไฟล์ | เหตุผล |
|------|--------|
| `src/hub.rs` | Clients map + broadcast ไม่เปลี่ยน |
| `src/stats.rs` | Stats struct ไม่เปลี่ยน |
| `src/protocol.rs` | Message types ไม่เปลี่ยน |

### ไฟล์ที่เปลี่ยน

**`profile-a/rust/src/main.rs`**:
```rust
#[derive(Clone)]
struct AppState { clients: Clients, stats: Arc<Mutex<Stats>> }

async fn ws_handler(
    ws: WebSocketUpgrade,
    State(state): State<AppState>,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_connection(socket, state.clients, state.stats))
}

#[tokio::main]
async fn main() {
    let state = AppState { clients: new_clients(), stats: Arc::new(Mutex::new(Stats::new())) };
    let app = Router::new()
        .route("/ws", get(ws_handler))
        .route("/health", get(|| async { "ok" }))
        .with_state(state.clone());

    let listener = TcpListener::bind(format!("0.0.0.0:{}", cli.port)).await.unwrap();
    eprintln!("listening on :{}", cli.port);

    let serve = axum::serve(listener, app);
    if cli.duration > 0 {
        tokio::select! {
            _ = serve => {}
            _ = tokio::time::sleep(Duration::from_secs(cli.duration)) => {}
        }
    } else { serve.await.unwrap(); }

    state.stats.lock().await.print_stats();
}
```

**`profile-a/rust/src/client.rs`** — เปลี่ยน signature + Message type:

| Profile B | Profile A |
|-----------|-----------|
| `accept_async(TcpStream)` | ได้ `WebSocket` จาก axum โดยตรง |
| `WsMessage::Text(Utf8Bytes)` | `Message::Text(String)` |
| `Result<WsMessage, tungstenite::Error>` | `Result<Message, axum::Error>` |
| sink: `SplitSink<WebSocketStream<TcpStream>, WsMessage>` | sink: `SplitSink<WebSocket, Message>` |

rate limiter, ping/pong, broadcast — ไม่เปลี่ยนเลย

**`profile-a/rust/Cargo.toml`**:
```toml
[package]
name = "websocket-public-chat-profile-a"
version = "0.1.0"
edition = "2021"

[dependencies]
axum        = { version = "0.7", features = ["ws"] }
tokio       = { version = "1", features = ["full"] }
futures-util = "0.3"
serde       = { version = "1", features = ["derive"] }
serde_json  = "1"
uuid        = { version = "1", features = ["v4"] }
clap        = { version = "4", features = ["derive"] }
```

**`profile-a/rust/Dockerfile`** — Rust template จาก CLAUDE.md:
```dockerfile
FROM rust:1.85-bookworm AS builder
# ... (cache deps layer เหมือนเดิม)
# binary strip: websocket-public-chat-profile-a → ตรงกับ name ใน Cargo.toml

FROM debian:bookworm-slim
# ... ca-certificates
ENTRYPOINT ["/usr/local/bin/websocket-public-chat"]
```

---

## Phase 5 — run-profile-a.sh (เขียนใหม่เต็ม)

Clone logic จาก `run-profile-b.sh` เปลี่ยน:
- `RESULT_FILE` → `websocket_profile_a_${TIMESTAMP}.txt`
- `build_image`: ชี้ `$PROJECT_DIR/profile-a/$lang/`
- Image names: `wsca-go`, `wsca-rust`, `wsca-zig`
- Container names: `${lang}-a-${scenario}` (ไม่ชนกับ profile-b)
- Banner: `Profile A`
- Temp files: `/tmp/wsca_${lang}_${scenario}_tp`
- Server args: เหมือนกัน (same CLI interface)

---

## Phase 6 — README.md

อัปเดต 2 จุด:
1. Directory tree — เพิ่ม `profile-a/` และ `profile-b/`
2. Benchmark section — ระบุ script ทั้งสอง + image naming

---

## สรุปไฟล์ทั้งหมด

| Action | Files |
|--------|-------|
| `git mv` | `go/ → profile-b/go/`, `rust/ → profile-b/rust/`, `zig/ → profile-b/zig/` |
| แก้ (2 จุด) | `benchmark/run-profile-b.sh` |
| copy ตรงๆ | `profile-a/zig/` (จาก `profile-b/zig/`) |
| สร้างใหม่ | `profile-a/go/{main.go, client.go, hub.go, stats.go, protocol.go, go.mod, Dockerfile}` |
| สร้างใหม่ | `profile-a/rust/src/{main.rs, client.rs, hub.rs, stats.rs, protocol.rs}`, `Cargo.toml`, `Dockerfile` |
| เขียนใหม่ | `benchmark/run-profile-a.sh` |
| อัปเดต | `README.md` |

## Image naming

| Profile | Go | Rust | Zig |
|---------|----|------|-----|
| B (minimal) | `wsc-go` | `wsc-rust` | `wsc-zig` |
| A (framework) | `wsca-go` | `wsca-rust` | `wsca-zig` |

## ไม่มีอะไร shared ระหว่าง profile-a/ และ profile-b/

ทุก directory compile อิสระ — Dockerfile แยก, go.mod แยก, Cargo.toml แยก, build.zig.zon แยก
