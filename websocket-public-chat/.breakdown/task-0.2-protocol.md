# Task 0.2: Message Protocol Constants + JSON Helpers

## Status
[TODO]

## Description
กำหนด message schema, constants, และ helper functions ที่ใช้ร่วมกันทุกภาษา ต้องตกลงให้ชัดก่อนเขียน server logic

## Acceptance Criteria
- [ ] Protocol document ใน `docs/protocol.md` (หรือใน README) ระบุ:
  - JSON schema แต่ละ message type ครบ
  - ขนาด chat payload = 128 bytes (padding strategy)
  - Error behavior: rate limit drop (ไม่ disconnect), unknown type = ignore
- [ ] Go: `protocol.go` — struct สำหรับ Message, constants, `padToSize()` helper
- [ ] Rust: `protocol.rs` — `#[derive(Serialize, Deserialize)]` Message enum/struct, constants
- [ ] Zig: `protocol.zig` — comptime string constants, struct definitions

## Tests Required
- [ ] Go: unit test `TestPadToSize` — ตรวจว่า `padToSize("hello", 128)` ให้ผล 128 bytes
- [ ] Go: unit test `TestMarshalChat` — marshal/unmarshal chat message ได้ถูกต้อง
- [ ] Rust: unit test `test_pad_to_size` + `test_serde_roundtrip`
- [ ] Zig: unit test `test_parse_json_message` — parse `{"type":"chat",...}` ได้ถูกต้อง

## Dependencies
- Task 0.1 (project skeleton)

## Files Affected
```
go/protocol.go
rust/src/protocol.rs
zig/src/protocol.zig
docs/protocol.md (หรือ docs section ใน README)
```

## Protocol Definition

```go
// Message types
const (
    MsgJoin  = "join"
    MsgChat  = "chat"
    MsgPing  = "ping"
    MsgPong  = "pong"
    MsgLeave = "leave"
)

type Message struct {
    Type string `json:"type"`
    Room string `json:"room,omitempty"`
    User string `json:"user,omitempty"`
    Text string `json:"text,omitempty"`
    Ts   int64  `json:"ts,omitempty"`
}

const ChatPayloadSize = 128
const Room = "public"
const RateLimitMsgPerSec = 10
const PingIntervalSec = 30
```

## Notes
- `text` field ใน chat message ต้อง pad ด้วย space หรือ random chars ให้ครบ 128 bytes รวม JSON overhead
- ให้ตกลง exact byte count รวม JSON syntax: `{"type":"chat","user":"client-XX","text":"..."}` ≈ 50 bytes overhead → text body ≈ 78 chars
- Rust: ใช้ `serde_json::Value` หรือ enum `MsgType` — ตัดสินใจตอนเขียน code
