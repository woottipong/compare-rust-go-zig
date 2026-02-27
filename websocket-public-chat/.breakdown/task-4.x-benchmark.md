# Task 4.1–4.4: Benchmark Harness

## Status
[TODO]

---

## Task 4.1: Steady Scenario Integration Test

### Acceptance Criteria
- [ ] `k6/steady.js` รันกับ server จริงทั้ง 3 ภาษาได้
- [ ] collect: `throughput`, `avg latency`, `p95`, `p99`, `connection success rate`
- [ ] parse k6 output จาก stdout ได้ด้วย bash

### Tests Required
- [ ] รัน steady 10s กับแต่ละ language server → ได้ตัวเลขออกมา ไม่ error

---

## Task 4.2: Burst + Churn Scenarios

### Acceptance Criteria
- [ ] `k6/burst.js`: 1000 VUs in 10s → วัด connection success rate
- [ ] `k6/churn.js`: 200 steady VUs, 10 disconnect+reconnect ทุก 2s → วัด stability
- [ ] ทุก scenario collect metrics ในรูปแบบเดียวกัน

---

## Task 4.3: benchmark/run.sh — Profile B ทุกภาษา

### Acceptance Criteria
- [ ] รัน 3 scenarios × 3 ภาษา = 9 benchmark runs อัตโนมัติ
- [ ] Docker: build server image → start server container → start k6 container → collect → stop server
- [ ] Docker network: `ws-bench-net` สร้าง + cleanup เสมอ
- [ ] Auto-save: `benchmark/results/ws-chat_<timestamp>.txt`
- [ ] Display: Avg/P95/P99 latency, throughput, connection success rate, binary size

### Script Flow
```bash
setup_network()         # docker network create ws-bench-net
start_server <image>    # docker run -d --network ws-bench-net --name ws-server <image>
run_k6 <scenario>       # docker run --rm --network ws-bench-net grafana/k6 ...
stop_server()           # docker stop ws-server && docker rm ws-server
cleanup_network()       # docker network rm ws-bench-net (ใน trap EXIT)
```

### Parse k6 Output
```bash
# k6 output line: "chat_msgs_sent.................: 6000  100/s"
throughput=$(k6_output | grep "chat_msgs_sent" | awk '{print $NF}' | tr -d '/s')
p95=$(k6_output | grep "ws_session_duration" | grep -oP 'p\(95\)=\K[0-9.]+')
```

## Dependencies
- Task 0.3 (k6 scripts)
- Task 1.3 (Go server done)
- Task 2.3 (Rust server done)
- Task 3.4 (Zig server done)

## Files Affected
```
benchmark/run.sh
benchmark/run-profile-a.sh   # placeholder
benchmark/results/
```

---

## Task 4.4: README + Results Table

### Acceptance Criteria
- [ ] README มี: purpose, structure, dependencies, build commands, benchmark table
- [ ] Benchmark table แสดง Steady scenario สำหรับทุกภาษา (Avg/P95/P99/throughput)
- [ ] Key insight section: "ทำไมภาษา X ชนะ"

## Full Dependencies Chain

```
1.3 ─┐
2.3 ──┼─→ 4.1 → 4.2 → 4.3 → 4.4
3.4 ─┘
       ↑
      0.3 (k6 scripts)
```

## Notes
- **Server --duration flag**: server ควรรัน indefinitely (ไม่ต้องมี duration ถ้า k6 เป็นตัวควบคุม)
  - หรือ server รับ `--duration 120` เพื่อ auto-shutdown หลัง benchmark
  - **แนะนำ**: ให้ benchmark script จัดการ `docker stop` แทน
- **Fairness**: server warm-up 5 วินาที ก่อนเริ่ม k6 (sleep 5 ใน script)
- **Binary size**: `docker create` + `docker cp` + `wc -c` เหมือน projects อื่น
