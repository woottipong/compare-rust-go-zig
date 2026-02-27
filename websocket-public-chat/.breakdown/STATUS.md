# WebSocket Public Chat — Project Status

> อัปเดตล่าสุด: 2026-02-28 | Phase: IMPROVE
> Progress: █████████████░░░ 80% (16/20 tasks done)

---

## Epic 0: Foundation & Protocol
| Task | Description | Status | Priority | Depends On |
|------|-------------|--------|:--------:|------------|
| 0.1 | Project skeleton + Dockerfile templates | [DONE] | — | — |
| 0.2 | Message protocol constants + JSON helpers | [DONE] | — | 0.1 |
| 0.3 | k6 load-test scripts (3 scenarios) | [DONE] | — | 0.1, 0.2 |
| 0.4 | Resolve Open Questions (Zig WS, Docker, rate limit) | [DONE] | — | — |

---

## Epic 1: Profile B — Go (net/http + gorilla/websocket)
| Task | Description | Status | Priority | Depends On |
|------|-------------|--------|:--------:|------------|
| 1.1 | WS server core: connect, join, broadcast | [DONE] | — | 0.1, 0.2 |
| 1.2 | Ping/Pong keepalive (30s) + rate limit (10 msg/s) | [DONE] | — | 1.1 |
| 1.3 | Stats struct + Docker + unit tests | [DONE] | — | 1.2 |

---

## Epic 2: Profile B — Rust (tokio + tokio-tungstenite)
| Task | Description | Status | Priority | Depends On |
|------|-------------|--------|:--------:|------------|
| 2.1 | WS server core: connect, join, broadcast | [DONE] | — | 0.1, 0.2 |
| 2.2 | Ping/Pong keepalive (30s) + rate limit (10 msg/s) | [DONE] | — | 2.1 |
| 2.3 | Stats struct + Docker + unit tests | [DONE] | — | 2.2 |

---

## Epic 3: Profile B — Zig (zap v0.11 / facil.io)
| Task | Description | Status | Priority | Depends On |
|------|-------------|--------|:--------:|------------|
| 3.1 | Verify Zig WS library (zap v0.11) | [DONE] | — | 0.4 |
| 3.2 | WS server core: connect, join, broadcast | [DONE] | — | 3.1 |
| 3.3 | Ping/Pong keepalive (30s) + rate limit (10 msg/s) | [DONE] | — | 3.2 |
| 3.4 | Stats struct + Docker + unit tests | [DONE] | — | 3.3 |

---

## Epic 4: Benchmark Harness
| Task | Description | Status | Priority | Depends On |
|------|-------------|--------|:--------:|------------|
| 4.1 | Steady scenario: 100 clients, 1 msg/sec, 60s | [DONE] | — | 0.3, 1.3 |
| 4.2 | Burst scenario: 1000 clients in 10s | [DONE] | — | 4.1 |
| 4.3 | Churn scenario: 200 steady + connect/disconnect loop | [DONE] | — | 4.1 |
| 4.4 | benchmark/run.sh: Profile B all languages + auto-save | [DONE] | — | 4.1, 2.3, 3.4 |

---

## Epic 5: Profile A — Framework Servers
| Task | Description | Status | Priority | Depends On |
|------|-------------|--------|:--------:|------------|
| 5.1 | Go (GoFiber): Docker build verify + unit tests | [DONE] | — | 4.4 |
| 5.2 | Rust (Axum): Docker build verify + unit tests | [DONE] | — | 4.4 |
| 5.3 | Zig (zap copy): Docker build verify | [DONE] | — | 3.4 |
| 5.4 | run-profile-a.sh + Profile B vs A comparison + README | [DONE] | — | 5.1, 5.2, 5.3 |

---

## Epic 6: 🔴 Rust Performance Fix (Critical)
| Task | Description | Status | Priority | Depends On |
|------|-------------|--------|:--------:|------------|
| 6.1 | Rust Stats: เปลี่ยน Arc\<Mutex\<Stats\>\> → AtomicU64 (Profile A+B) | [DONE] | 🔴 | — |
| 6.2 | Rust Broadcast: แก้ blocking await ใน RwLock → try_send (Profile A+B) | [DONE] | 🔴 | — |
| 6.3 | Rust: รัน unit tests verify refactor ไม่ break | [DONE] | 🔴 | 6.1, 6.2 |

---

## Epic 7: 🟡 Go Performance Fix (Medium)
| Task | Description | Status | Priority | Depends On |
|------|-------------|--------|:--------:|------------|
| 7.1 | Go: ลด sendBufSize 256→64 + ลด Read/WriteBufferSize (Profile A+B) | [DONE] | 🟡 | — |
| 7.2 | Go: รัน unit tests verify | [DONE] | 🟡 | 7.1 |

---

## Epic 8: 🟡 Benchmark Methodology Improvement
| Task | Description | Status | Priority | Depends On |
|------|-------------|--------|:--------:|------------|
| 8.1 | Script: เพิ่ม CPU sampling + pin resources (--cpus/--memory) | [DONE] | 🟡 | — |
| 8.2 | Script: เพิ่ม multi-run (3x) + randomize order + stdev | [DONE] | 🟡 | 8.1 |
| 8.3 | k6: เพิ่ม E2E latency metric ใน steady.js | [DONE] | 🟡 | — |

---

## Epic 9: Documentation & Re-benchmark
| Task | Description | Status | Priority | Depends On |
|------|-------------|--------|:--------:|------------|
| 9.1 | รัน benchmark ใหม่ทั้ง Profile A+B หลังแก้ code | [TODO] | — | 6.3, 7.2, 8.2 |
| 9.2 | อัปเดต README.md ด้วยผลใหม่ + improvement notes | [TODO] | — | 9.1 |

---

## Critical Path (Epic 6–9)

```
Epic 6 (Rust fix) ──────→ 6.3 ─┐
Epic 7 (Go fix) ─────────→ 7.2 ─┼─→ 9.1 (Re-benchmark) → 9.2 (README)
Epic 8 (Bench improve) → 8.2 ──┘
         8.3 (k6 latency) ─────┘
```

แนะนำลำดับการทำ:
1. **Epic 6** — แก้ Rust ก่อน เพราะเป็น critical issue (🔴)
2. **Epic 7** — แก้ Go memory ต่อ (🟡 ง่าย เร็ว)
3. **Epic 8** — ปรับ benchmark methodology (🟡)
4. **Epic 9** — รัน benchmark ใหม่ + อัปเดต docs

---

## Legend
- [TODO] — ยังไม่เริ่ม
- [IN PROGRESS] — กำลังทำอยู่
- [DONE] — เสร็จแล้ว test ผ่านทั้งหมด
- [BLOCKED] — รอ dependency หรือมีปัญหาต้องแก้ก่อน
- 🔴 Critical  🟡 Medium  🟢 Low
