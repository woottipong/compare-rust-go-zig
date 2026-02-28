# Task 5.1–5.4: Profile A — Framework Servers

## Status
[DONE]

## Priority
— (build task)

## Description
Implement + verify Profile A (framework version) ขอ 3 ภาษา แล้ว benchmark เปรียบเทียบกับ Profile B เพื่อวัด delta ที่มาจาก framework abstraction — ตอบคำถาม "framework เพิ่ม/ลด performance เท่าไหร่?"

---

## Task 5.1: Go (GoFiber) — Verify + Unit Tests

### Acceptance Criteria
- [x] `docker build -t wsca-go profile-a/go/` ผ่าน
- [x] `docker run --rm wsca-go --duration 1` ไม่ crash
- [x] `hub_test.go`: `TestHubRegisterUnregister` + `TestBroadcastToOthers` ผ่าน
- [x] `stats_test.go`: `TestStatsAvgLatency` + `TestStatsThroughput` ผ่าน
- [x] `client_test.go`: `TestRateLimiter` ผ่าน
- [x] `go test ./...` ผ่าน local

### Tests Required
```
profile-a/go/hub_test.go     — TestHubRegisterUnregister, TestBroadcastToOthers
profile-a/go/stats_test.go   — TestStatsAvgLatency, TestStatsThroughput
profile-a/go/client_test.go  — TestRateLimiter
```

### Notes
- hub.go เหมือน profile-b/go ทุกประการ → test ใช้ logic เดิม
- client.go ใช้ `gofiber/websocket.Conn` แทน gorilla → API เหมือนกัน
- ห้ามแก้ logic เพื่อให้ test ผ่าน — ถ้า fail แปลว่า code มีปัญหา

---

## Task 5.2: Rust (Axum) — Docker Build Verify

### Acceptance Criteria
- [x] `cargo test --manifest-path profile-a/rust/Cargo.toml` ผ่าน (7 tests)
- [x] `docker build -t wsca-rust profile-a/rust/` ผ่าน
- [x] `docker run --rm wsca-rust --port 8080 --duration 1` ไม่ crash

### Tests Required
- ไม่ต้องเพิ่ม — Rust มี tests ครบทุก module อยู่แล้ว:
  - `hub.rs`: `test_broadcast_to_others`, `test_state_cleanup`
  - `client.rs`: `test_rate_limit_drop`, `test_rate_limit_refill`
  - `stats.rs`: `test_stats_counters`, `test_stats_format`
  - `protocol.rs`: `test_pad_to_size`, `test_serde_roundtrip`

### Notes
- ถ้า `cargo test` fail อาจมี type mismatch: `axum::extract::ws::Message` vs test code
- ถ้า Docker build fail: ตรวจ binary name → ต้องตรงกับ `name` ใน Cargo.toml

---

## Task 5.3: Zig (zap copy) — Docker Build Verify

### Acceptance Criteria
- [x] `docker build -t wsca-zig profile-a/zig/` ผ่าน
- [x] `docker run --rm wsca-zig 8080 1` start ได้ + print stats ก่อน exit
- [x] Binary size ≤ 5MB (เหมือน profile-b/zig)

### Tests Required
- Smoke test: docker run ไม่ crash
- ไม่ต้องเขียน unit tests เพิ่ม — code เหมือน profile-b ที่ผ่านแล้ว

### Notes
- ถ้า Docker build fail: ตรวจ `build.zig.zon` → ต้องมี `.fingerprint` field
- Image tag: `wsca-zig` (ไม่ใช่ `wsc-zig`)

---

## Task 5.4: Benchmark + README + Profile B vs A Comparison

### Acceptance Criteria
- [x] `bash benchmark/run-profile-a.sh` รันสำเร็จ
- [x] ผล auto-save ใน `benchmark/results/websocket_profile_a_<timestamp>.txt`
- [x] README.md มี "Profile A vs Profile B" comparison table:

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

- [x] README มี "Key Insight" section: framework delta analysis
- [x] STATUS.md: Task 5.1–5.4 → [DONE]

### Tests Required
- Benchmark run ผ่าน: 3 scenarios × 3 ภาษา = 9 runs ไม่ error

---

## Dependencies
```
4.4 (profile-b benchmark done) ─┬─→ 5.1 (go verify+test)   ─┐
                                 ├─→ 5.2 (rust verify+test)  ─┼─→ 5.4 (benchmark + README)
3.4 (zig profile-b done) ──────→ 5.3 (zig verify)           ─┘
```

## Files Affected
```
profile-a/go/{hub,stats,client}_test.go    # สร้างใหม่
README.md                                   # เพิ่ม Profile A vs B section
.breakdown/STATUS.md                        # Epic 5 → [DONE]
benchmark/results/                          # auto-generated
```

## Implementation Notes

### Execution Order (parallel ได้)
1. **5.1** — Go: docker build + go test
2. **5.2** — Rust: docker build + cargo test (parallel กับ 5.1)
3. **5.3** — Zig: docker build verify (parallel กับ 5.1, 5.2)
4. **5.4** — Benchmark run + README (sequential, ต้องรอ 5.1-5.3)

### Code Status Summary
| Component | Go | Rust | Zig |
|-----------|:--:|:----:|:---:|
| Server code | ✓ GoFiber | ✓ Axum 0.7 | ✓ copy profile-b |
| Hub/Stats/Protocol | ✓ identical B | ✓ identical B | ✓ identical B |
| Unit tests | ✓ ported | ✓ ครบทุก module | — (code = profile-b) |
| Docker build | ✓ | ✓ | ✓ |

### Open Questions (resolved)
| คำถาม | คำตอบ |
|-------|-------|
| Go fiber.Conn mock สำหรับ test? | ใช้ pattern เดิมจาก profile-b: test hub ตรงๆ ไม่ mock WS |
| Rust axum.Message type mismatch? | แก้ client.rs — hub.rs/stats.rs ไม่เปลี่ยน |
| Zig build.zig.zon fingerprint? | Unique per project, รัน `zig build` เพื่อ suggested value |
