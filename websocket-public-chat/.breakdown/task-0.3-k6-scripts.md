# Task 0.3: k6 Load-Test Scripts (3 Scenarios)

## Status
[DONE]

## Priority
— (build task)

## Description
เขียน k6 JavaScript scripts สำหรับ 3 benchmark scenarios (Steady, Burst, Churn) โดยใช้ `k6/ws` API — เป็นเครื่องมือวัดผลกลางที่ทุกภาษาใช้ร่วมกัน ต้อง collect metrics ในรูปแบบเดียวกันเพื่อความ fair

## Acceptance Criteria
- [x] `k6/steady.js`: 100 VUs, 1 msg/sec ต่อ VU, duration 60s
- [x] `k6/burst.js`: ramp 0→1,000 VUs ใน 10s, hold 5s, ramp down 5s
- [x] `k6/churn.js`: 200 VUs constant, ทุก iteration = connect→join→2s→leave→disconnect
- [x] ทุก script collect: `ws_msgs_sent`, `ws_msgs_received`, `ws_session_duration`, `checks`
- [x] ทุก script รับ env var `WS_URL` (default: `ws://localhost:8080/ws`)
- [x] ทุก script export JSON summary ที่ parse ได้ใน bash
- [x] `k6/Dockerfile` พร้อมรัน (`grafana/k6:latest`)

## Tests Required
- [x] `k6 run --vus 1 --duration 5s k6/steady.js` กับ echo server → ไม่ error
- [x] verify ว่า output มี `checks` metric ครบ

## Dependencies
- Task 0.1 (k6 directory), Task 0.2 (message schema)

## Files Affected
```
k6/steady.js
k6/burst.js
k6/churn.js
k6/Dockerfile
```

## Implementation Notes

### Run Command
```bash
docker run --rm --network ws-bench-net \
  -e WS_URL=ws://ws-server:8080/ws \
  -v "$K6_DIR":/scripts:ro \
  grafana/k6 run /scripts/steady.js
```

### Metrics ที่ต้อง Collect
| Metric | Source | ใช้สำหรับ |
|--------|--------|-----------|
| `chat_msgs_sent` | Custom Counter | Throughput |
| `chat_msgs_received` | Custom Counter | Drop rate |
| `ws_session_duration` | k6 built-in | Latency p95/p99 |
| `checks` | k6 built-in | Connection success rate |

### k6 Behavior
- เมื่อรับ `ping` → ตอบ `pong` ทันที (protocol compliance)
- เมื่อรับ `chat` → increment `msgsReceived` counter
- steady.js: ส่ง 1 msg/sec ด้วย `setInterval(fn, 1000)`
- burst.js: connect + join + hold 5s + leave → ไม่ส่ง chat (วัด connection handling)
- churn.js: connect→join→wait 2s→leave→close → วน loop ตลอด duration
