# WebSocket Public Chat

WebSocket Public Chat benchmark project for comparing Go, Rust, and Zig implementations.

## Project Status

Current progress:

- ✅ Task 0.1: Project skeleton + Docker templates
- ✅ Task 0.2: Shared protocol constants + JSON helpers
- ⏳ Server/runtime tasks: in progress

## Directory Structure

```text
websocket-public-chat/
├── go/
├── rust/
├── zig/
├── k6/
├── benchmark/
└── docs/
```

## Shared Protocol

Protocol spec is documented in:

- `docs/protocol.md`

Key constants:

- `ChatPayloadSize = 128`
- `Room = "public"`
- `RateLimitMsgPerSec = 10`
- `PingIntervalSec = 30`

Message types:

- `join`, `chat`, `ping`, `pong`, `leave`

Error behavior:

- Rate limit exceeded: drop message (no disconnect)
- Unknown message type: ignore
- Malformed JSON: ignore

## Implemented in Task 0.2

### Go

- `go/protocol.go`
  - `Message` struct
  - Protocol constants
  - `padToSize()` helper
  - `marshalChatMessage()` helper (target serialized payload = 128 bytes)
- `go/protocol_test.go`
  - `TestPadToSize`
  - `TestMarshalChat`

### Rust

- `rust/src/protocol.rs`
  - `Message` struct with `serde` derive
  - Protocol constants
  - `pad_to_size()` helper
  - Unit tests: `test_pad_to_size`, `test_serde_roundtrip`

### Zig

- `zig/src/protocol.zig`
  - Protocol constants
  - `Message` struct
  - Unit test: `test_parse_json_message`

## How to Run Tests

### Go

```bash
go test ./...
```

### Rust

```bash
cargo test
```

### Zig

```bash
zig test src/protocol.zig
```

## Docker Build

Each language has its own Dockerfile:

- `go/Dockerfile`
- `rust/Dockerfile`
- `zig/Dockerfile`

Example build commands:

```bash
docker build -t wsc-go ./go
docker build -t wsc-rust ./rust
docker build -t wsc-zig ./zig
```

## Benchmark

Benchmark script placeholder:

- `benchmark/run.sh`

> Full benchmark implementation is planned in task 4.4.
