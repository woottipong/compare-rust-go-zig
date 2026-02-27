# Task 0.2: Message Protocol Constants + JSON Helpers

## Status
[DONE]

## Priority
— (build task)

## Description
กำหนด message schema, constants, และ helper functions ที่ใช้ร่วมกันทุกภาษา — ต้องตกลงให้ชัดก่อนเขียน server logic เพื่อให้ทุกภาษา interop กันได้ผ่าน k6 test scripts ชุดเดียวกัน

## Acceptance Criteria
- [x] `docs/protocol.md` ระบุ JSON schema ทุก message type ครบ
- [x] ขนาด chat payload = 128 bytes (รวม JSON overhead)
- [x] Error behavior: rate limit → drop (ไม่ disconnect), unknown type → ignore
- [x] Go: `protocol.go` — Message struct, constants, `padToSize()` helper
- [x] Rust: `protocol.rs` — `#[derive(Serialize, Deserialize)]` Message struct, constants
- [x] Zig: `protocol.zig` — comptime string constants, struct definitions

## Tests Required
- [x] Go: `TestPadToSize` — `padToSize("hello", 128)` → 128 bytes
- [x] Go: `TestMarshalChat` — marshal/unmarshal roundtrip
- [x] Rust: `test_pad_to_size` + `test_serde_roundtrip`
- [x] Zig: `test_parse_json_message` — parse `{"type":"chat",...}` ถูกต้อง

## Dependencies
- Task 0.1 (project skeleton)

## Files Affected
```
profile-b/go/protocol.go
profile-b/rust/src/protocol.rs
profile-b/zig/src/protocol.zig
docs/protocol.md
```

## Implementation Notes

### Protocol Constants (ทุกภาษาต้องตรงกัน)
```
Message Types : join, chat, ping, pong, leave
Chat Payload  : 128 bytes (text body ≈ 78 chars หลังหัก JSON overhead ≈ 50 bytes)
Room          : "public" (single room)
Rate Limit    : 10 msg/sec per client
Ping Interval : 30 seconds
```

### Padding Strategy
- `text` field ใน chat message pad ด้วย space ให้ครบ 128 bytes รวม JSON syntax
- Rust: ใช้ `serde_json::Value` หรือ enum `MsgType` — decision ตอนเขียน code
