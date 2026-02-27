# WebSocket Public Chat — Project Status

> อัปเดตล่าสุด: 2026-02-27 | ALL EPICS DONE — Project Complete
> Workflow: ดู WORKFLOW.md ใน root repo

---

## Epic 0: Foundation & Protocol (ต้องทำก่อนทุก epic)

| Task | Description | Status | Depends On |
|------|-------------|--------|------------|
| 0.1 | Project skeleton + Dockerfile templates | [DONE] | — |
| 0.2 | Message protocol constants + JSON helpers | [DONE] | 0.1 |
| 0.3 | k6 load-test scripts (3 scenarios) | [DONE] | 0.2 |
| 0.4 | Resolve Open Questions (Zig WS lib, k6 Docker) | [DONE] | — |

---

## Epic 1: Profile B — Go (net/http + gorilla/websocket)

| Task | Description | Status | Depends On |
|------|-------------|--------|------------|
| 1.1 | WS server core: connect, join, broadcast | [DONE] | 0.1, 0.2 |
| 1.2 | Ping/Pong keepalive (30s) + rate limit (10 msg/s) | [DONE] | 1.1 |
| 1.3 | Stats struct + Docker + unit tests | [DONE] | 1.2 |

---

## Epic 2: Profile B — Rust (tokio + tokio-tungstenite)

| Task | Description | Status | Depends On |
|------|-------------|--------|------------|
| 2.1 | WS server core: connect, join, broadcast | [DONE] | 0.1, 0.2 |
| 2.2 | Ping/Pong keepalive (30s) + rate limit (10 msg/s) | [DONE] | 2.1 |
| 2.3 | Stats struct + Docker + unit tests | [DONE] | 2.2 |

---

## Epic 3: Profile B — Zig (std.net / zap)

| Task | Description | Status | Depends On |
|------|-------------|--------|------------|
| 3.1 | Verify Zig WS library (zap v0.11 or manual) | [DONE] | 0.4 |
| 3.2 | WS server core: connect, join, broadcast | [DONE] | 3.1 |
| 3.3 | Ping/Pong keepalive (30s) + rate limit (10 msg/s) | [DONE] | 3.2 |
| 3.4 | Stats struct + Docker + unit tests | [DONE] | 3.3 |

---

## Epic 4: Benchmark Harness

| Task | Description | Status | Depends On |
|------|-------------|--------|------------|
| 4.1 | Steady scenario: 100 clients, 1 msg/sec, 60s | [DONE] | 0.3, 1.3 |
| 4.2 | Burst scenario: 1000 clients in 10s | [DONE] | 4.1 |
| 4.3 | Churn scenario: 200 steady + 10 connect/disconnect per 2s | [DONE] | 4.1 |
| 4.4 | benchmark/run.sh: Profile B all languages + auto-save | [DONE] | 4.1, 2.3, 3.4 |

---

## Epic 5: Profile A — Framework Servers (secondary)

| Task | Description | Status | Depends On |
|------|-------------|--------|------------|
| 5.1 | Go: GoFiber + websocket (reuse k6 scenarios) | [TODO] | 4.4 |
| 5.2 | Rust: Axum + tokio-tungstenite | [TODO] | 4.4 |
| 5.3 | Zig: zap framework (if WS supported) | [TODO] | 4.4 |
| 5.4 | benchmark/run-profile-a.sh + Profile B vs A comparison | [TODO] | 5.1, 5.2, 5.3 |

---

## Legend

| Status | ความหมาย |
|--------|----------|
| [TODO] | ยังไม่เริ่ม |
| [IN PROGRESS] | กำลังทำอยู่ |
| [DONE] | เสร็จแล้ว และ test ผ่านทั้งหมด |
| [BLOCKED] | รอ dependency หรือมีปัญหาต้องแก้ก่อน |

---

## Critical Path

```
0.4 (Open Questions) ─┐
0.1 → 0.2 → 0.3 ──────┼─→ 1.1 → 1.2 → 1.3 ─┐
                       ├─→ 2.1 → 2.2 → 2.3 ──┼─→ 4.1 → 4.2 → 4.3 → 4.4 ─→ 5.x
                       └─→ 3.1 → 3.2 → 3.3 → 3.4 ─┘
```

แนะนำลำดับการทำ:
1. **Task 0.4 ก่อน** — resolve Zig WS library (ถ้าไม่มี ต้องเปลี่ยน approach)
2. **Epic 0** — protocol + k6 scripts
3. **Epic 1** (Go) — implement ก่อนเพราะ gorilla/websocket ตรงไปตรงมา
4. **Epic 2** (Rust) — tokio + tungstenite ซับซ้อนกว่า ทำหลัง Go
5. **Epic 3** (Zig) — ขึ้นกับผล 0.4
6. **Epic 4** — harness รวม + benchmark run
7. **Epic 5** — profile A (optional, ทำเมื่อ B เสร็จแล้ว)
