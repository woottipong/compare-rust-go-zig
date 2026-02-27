# Task 4.1–4.4: Benchmark Harness

## Status
[DONE]

## Priority
— (build task)

## Description
สร้าง benchmark harness ที่รัน 3 scenarios × 3 ภาษา = 9 benchmark runs อัตโนมัติ ผ่าน Docker — เป็นจุดศูนย์กลางในการวัดผลที่ทำซ้ำได้ (reproducible) และ fair across languages

---

## Task 4.1: Steady Scenario Integration Test

### Acceptance Criteria
- [x] `k6/steady.js` รันกับ server จริงทั้ง 3 ภาษาได้
- [x] Collect: throughput, avg latency, p95, p99, connection success rate
- [x] Parse k6 output จาก stdout ได้ด้วย bash

### Tests Required
- [x] Steady 10s กับแต่ละ language server → ได้ตัวเลข ไม่ error

---

## Task 4.2: Burst + Churn Scenarios

### Acceptance Criteria
- [x] `k6/burst.js`: 1000 VUs in 10s → วัด connection success rate
- [x] `k6/churn.js`: 200 steady VUs, connect/disconnect loop → วัด stability
- [x] ทุก scenario collect metrics ในรูปแบบเดียวกัน

---

## Task 4.3: benchmark/run.sh — Automated Pipeline

### Acceptance Criteria
- [x] 3 scenarios × 3 ภาษา = 9 benchmark runs อัตโนมัติ
- [x] Docker: build → start server → start k6 → collect → stop server
- [x] Docker network: `ws-bench-net` สร้าง + cleanup (trap EXIT)
- [x] Auto-save: `benchmark/results/ws-chat_<timestamp>.txt`
- [x] Display: Avg/P95/P99 latency, throughput, connection success rate, binary size

---

## Task 4.4: README + Results Table

### Acceptance Criteria
- [x] README มี: purpose, structure, dependencies, build commands, benchmark table
- [x] Benchmark table แสดง Steady scenario ทุกภาษา (Avg/P95/P99/throughput)
- [x] Key insight section

---

## Dependencies
- Task 0.3 (k6 scripts)
- Task 1.3 (Go server DONE)
- Task 2.3 (Rust server DONE)
- Task 3.4 (Zig server DONE)

```
0.3 ────┐
1.3 ──┐ │
2.3 ──┼─┴─→ 4.1 → 4.2 → 4.3 → 4.4
3.4 ──┘
```

## Files Affected
```
benchmark/run.sh                  # main benchmark script
benchmark/run-profile-b.sh        # Profile B runner
benchmark/run-profile-a.sh        # placeholder
benchmark/results/                 # auto-generated
README.md                         # project README
```

## Implementation Notes

### Script Flow
```bash
setup_network()         # docker network create ws-bench-net
start_server <image>    # docker run -d --network ws-bench-net --name ws-server <image>
sleep 5                 # warm-up
run_k6 <scenario>       # docker run --rm --network ws-bench-net grafana/k6 ...
stop_server()           # docker stop ws-server && docker rm ws-server
cleanup_network()       # docker network rm ws-bench-net (in trap EXIT)
```

### k6 Output Parsing
```bash
throughput=$(k6_output | grep "chat_msgs_sent" | awk '{print $NF}' | tr -d '/s')
p95=$(k6_output | grep "ws_session_duration" | grep -oP 'p\(95\)=\K[0-9.]+')
```

### Fairness Controls
- Server warm-up 5 วินาทีก่อนเริ่ม k6
- Binary size: `docker create` + `docker cp` + `wc -c`
- ทุก server ใช้ resource limits เดียวกัน (ถ้าเพิ่มใน Epic 8)
