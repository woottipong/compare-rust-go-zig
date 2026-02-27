# WebSocket Public Chat Protocol

This document defines the shared JSON message format and constants for Go, Rust, and Zig implementations.

## Constants

- `ChatPayloadSize`: `128` bytes
- `Room`: `"public"`
- `RateLimitMsgPerSec`: `10`
- `PingIntervalSec`: `30`

## Message Types

- `join`
- `chat`
- `ping`
- `pong`
- `leave`

## JSON Schema

All messages are JSON objects with a required `type` field.

```json
{
  "type": "chat",
  "room": "public",
  "user": "client-01",
  "text": "hello",
  "ts": 1700000000
}
```

Fields:

- `type` (string, required)
- `room` (string, optional)
- `user` (string, optional)
- `text` (string, optional)
- `ts` (integer, optional, unix timestamp)

## 128-byte Chat Payload Rule

For `chat` messages, the **serialized JSON payload** must be exactly `128` bytes.

Padding strategy:

1. Build base `chat` message JSON.
2. Compute serialized byte length.
3. If length is less than 128, append spaces (`" "`) to `text`.
4. If length is greater than 128, truncate `text` so the final JSON is exactly 128 bytes.

Notes:

- Padding/truncation is applied only to the `text` field.
- `text` is expected to be ASCII for deterministic byte counting in this benchmark profile.

## Error Behavior

- Rate limit exceeded: drop message (do not disconnect client).
- Unknown message type: ignore message.
- Malformed JSON: ignore message.
