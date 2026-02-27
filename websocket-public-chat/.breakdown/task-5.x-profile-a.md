# Task 5.1–5.4: Profile A — Framework Servers

## Status
[TODO] — code exists, ต้องผ่าน verification + unit tests ก่อน benchmark

---

## สถานะ Code ที่มีแล้ว (ณ 2026-02-27)

| Component | Go | Rust | Zig |
|-----------|----|----|-----|
| main.go / main.rs / main.zig | ✓ GoFiber | ✓ Axum 0.7 | ✓ copy profile-b |
| hub | ✓ identical to profile-b | ✓ identical to profile-b | ✓ identical to profile-b |
| client | ✓ gofiber/websocket API | ✓ axum::extract::ws | ✓ identical to profile-b |
| stats | ✓ identical to profile-b | ✓ identical to profile-b | ✓ identical to profile-b |
| protocol | ✓ identical to profile-b | ✓ identical to profile-b | ✓ identical to profile-b |
| Dockerfile | ✓ | ✓ | ✓ |
| go.mod / Cargo.toml | ✓ | ✓ | ✓ |
| unit tests | ✗ ยังไม่มี | ✓ ครบทุก module แล้ว | — (code เหมือน profile-b ที่ผ่านแล้ว) |

**ขาด:**
- Go: unit tests (hub_test.go, stats_test.go, client_test.go)
- Rust: Docker build verify เท่านั้น — tests มีครบใน hub.rs, client.rs, stats.rs, protocol.rs
- Zig: Docker build verify เท่านั้น
- ทั้งหมด: benchmark run, README update

> **ไม่มี refactor task** — code ทั้ง Go และ Rust สะอาด ไม่มี code smell
> pattern เหมือน profile-b ที่ผ่าน benchmark แล้ว ไม่ควร refactor ก่อน verify build

---

## Task 5.1: Profile A — Go (GoFiber) — Verify + Unit Tests

### Status
[TODO]

### Description
Code มีแล้ว (GoFiber v2 + gofiber/websocket/v2) ต้องผ่าน Docker build และ unit tests

### Acceptance Criteria
- [ ] `docker build -t wsca-go profile-a/go/` ผ่านโดยไม่ error
- [ ] `docker run --rm wsca-go --duration 1` start ได้และไม่ crash
- [ ] `hub_test.go`: `TestHubRegisterUnregister` + `TestBroadcastToOthers` ผ่าน (port จาก profile-b)
- [ ] `stats_test.go`: `TestStatsAvgLatency` + `TestStatsThroughput` ผ่าน (port จาก profile-b)
- [ ] `client_test.go`: `TestRateLimiter` ผ่าน (port จาก profile-b)
- [ ] `unset GOROOT && go test ./...` ผ่าน local

### Tests Required
```
profile-a/go/hub_test.go     — TestHubRegisterUnregister, TestBroadcastToOthers
profile-a/go/stats_test.go   — TestStatsAvgLatency, TestStatsThroughput
profile-a/go/client_test.go  — TestRateLimiter (no real WS conn needed)
```

### Notes
- hub.go ใน profile-a/go เหมือน profile-b/go ทุกประการ → test ใช้ logic เดิม
- client.go ใช้ `gofiber/websocket.Conn` แทน gorilla → readPump/writePump/allow() API เหมือนกัน
- ห้ามแก้ logic เพื่อให้ test ผ่าน — ถ้า test fail แปลว่า code มีปัญหา ให้แก้ code

### Dependencies
- Task 4.4

### Files Affected
```
profile-a/go/hub_test.go     (สร้างใหม่)
profile-a/go/stats_test.go   (สร้างใหม่)
profile-a/go/client_test.go  (สร้างใหม่)
```

---

## Task 5.2: Profile A — Rust (Axum) — Docker Build Verify

### Status
[TODO]

### Description
Rust มี tests ครบทุก module อยู่แล้ว:
- `hub.rs`: `test_broadcast_to_others`, `test_state_cleanup`
- `client.rs`: `test_rate_limit_drop`, `test_rate_limit_refill`
- `stats.rs`: `test_stats_counters`, `test_stats_format`
- `protocol.rs`: `test_pad_to_size`, `test_serde_roundtrip`

งาน: verify ว่า build + tests ผ่านจริง

### Acceptance Criteria
- [ ] `cargo test --manifest-path profile-a/rust/Cargo.toml` ผ่าน (7 tests)
- [ ] `docker build -t wsca-rust profile-a/rust/` ผ่านโดยไม่ error
- [ ] `docker run --rm wsca-rust --port 8080 --duration 1` start ได้และไม่ crash

### Tests Required
ไม่ต้องเพิ่ม — รัน tests ที่มีอยู่เพื่อ confirm เท่านั้น

### Notes
- ถ้า `cargo test` fail: อาจมี type mismatch ระหว่าง `axum::extract::ws::Message` กับ test code
- ถ้า Docker build fail: ตรวจ binary name ใน `strip` → ต้องตรงกับ `name` ใน Cargo.toml (`websocket-public-chat-profile-a`)

### Dependencies
- Task 4.4

### Files Affected
```
ไม่มีไฟล์ใหม่ — verify only
```

---

## Task 5.3: Profile A — Zig (zap) — Docker Build Verify

### Status
[TODO]

### Description
profile-a/zig/ เป็น copy ตรงๆ ของ profile-b/zig/ — ใช้ zap v0.11 เหมือนกัน
ต้องแค่ verify Docker build ด้วย image tag ใหม่

### Acceptance Criteria
- [ ] `docker build -t wsca-zig profile-a/zig/` ผ่านโดยไม่ error
- [ ] `docker run --rm wsca-zig 8080 1` start ได้และ print stats ก่อน exit
- [ ] binary size ≤ 5MB (เหมือน profile-b/zig)

### Tests Required
- smoke test: docker run ไม่ crash (เป็น acceptance criteria)
- ไม่ต้องเขียน unit tests เพิ่ม เพราะ code เหมือน profile-b ที่ผ่าน test แล้ว

### Notes
- ถ้า Docker build fail ให้ตรวจ build.zig.zon — ต้องมี `.fingerprint` field
- image tag: `wsca-zig` (ไม่ใช่ `wsc-zig`)

### Dependencies
- Task 3.4 (zig profile-b already done)

### Files Affected
```
ไม่มีไฟล์ใหม่ — แค่ verify
```

---

## Task 5.4: Benchmark + README + Profile B vs A Comparison

### Status
[TODO]

### Description
รัน `benchmark/run-profile-a.sh` เก็บผล และอัปเดต README ด้วย comparison table

### Acceptance Criteria
- [ ] `bash benchmark/run-profile-a.sh` รันสำเร็จ ไม่ crash ระหว่าง run
- [ ] ผล auto-save ใน `benchmark/results/websocket_profile_a_<timestamp>.txt`
- [ ] README.md มี section "Profile A vs Profile B" ที่แสดง:

```
| Language | Profile       | Steady (msg/s) | Burst (msg/s) | Churn (msg/s) |
|----------|--------------|----------------|---------------|---------------|
| Go       | B (net/http) | X              | X             | X             |
| Go       | A (fiber)    | X              | X             | X             |
| Rust     | B (tokio)    | X              | X             | X             |
| Rust     | A (axum)     | X              | X             | X             |
| Zig      | B (zap)      | X              | X             | X             |
| Zig      | A (zap copy) | X              | X             | X             |
```

- [ ] README มี "Key Insight" section: framework เพิ่ม/ลด latency เท่าไหร่
- [ ] STATUS.md: Task 5.1–5.4 เปลี่ยนเป็น [DONE]

### Tests Required
- Benchmark run ผ่านโดยไม่มี error สำหรับ 3 scenarios × 3 ภาษา = 9 runs

### Dependencies
- Task 5.1 (Go Docker ready)
- Task 5.2 (Rust Docker ready)
- Task 5.3 (Zig Docker ready)
- Task 0.3 (k6 scripts ready — [DONE])

### Files Affected
```
README.md               (อัปเดต — เพิ่ม Profile A vs B section)
.breakdown/STATUS.md    (อัปเดต — Epic 5 [DONE])
benchmark/results/      (auto-generated ไม่ commit)
```

---

## Full Dependencies Chain

```
4.4 (profile-b benchmark done) ─┬─→ 5.1 (go verify+test) ─┐
                                 ├─→ 5.2 (rust verify+test) ─┼─→ 5.4 (benchmark + README)
3.4 (zig profile-b done) ───────→ 5.3 (zig verify) ─────────┘
```

## Implementation Order

1. **5.1** — Go: docker build + go test
2. **5.2** — Rust: docker build + cargo test (parallel กับ 5.1)
3. **5.3** — Zig: docker build verify (parallel กับ 5.1, 5.2)
4. **5.4** — Benchmark run + README

## Open Questions

| คำถาม | คำตอบ |
|-------|-------|
| profile-a/go client.go ต้องการ `go test` mock สำหรับ fiber.Conn? | ใช้ pattern เดิมจาก profile-b: test hub ตรงๆ ไม่ต้อง mock WS |
| profile-a/rust client.rs อาจต้องแก้ port เพราะ axum.Message type? | ถ้า compile fail ให้แก้ client.rs — hub.rs/stats.rs ไม่เปลี่ยน |
| zig: build.zig.zon fingerprint ต่างจาก profile-b? | ใช่ — copy มาแล้ว fingerprint unique ต่อ project ดังนั้น อาจต้องรัน `zig build` เพื่อให้มันบอก suggested value |
