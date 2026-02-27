# Task 0.4: Resolve Open Questions

## Status
[TODO]

## Description
ค้นหาและตัดสินใจในประเด็นที่จะกระทบ architecture ก่อนเขียนโค้ด — ถ้า resolve ผิดต้อง refactor ทั้ง epic

## Questions ที่ต้อง Resolve

### Q1: Zig WebSocket Library
**คำถาม**: `zap` v0.11 (Zig 0.15) รองรับ WebSocket หรือไม่?

**วิธี verify**:
```bash
# อ่าน zap changelog/README
curl -s https://github.com/zigzap/zap/releases/tag/v0.11.0 | grep -i websocket
```

**ตัวเลือก**:
- A) `zap` มี WS → ใช้ zap (ง่ายที่สุด)
- B) `zap` ไม่มี WS → implement manual WS handshake + frame parser ใน std.net
- C) หา library อื่น: `zig-websocket` หรือ `ws.zig`

**Decision**: `_______` (กรอกหลัง verify)

---

### Q2: Docker Network สำหรับ k6 ↔ Server
**คำถาม**: ใช้ network ไหนให้ k6 container คุยกับ server container?

**วิธี**: Docker user-defined bridge network
```bash
docker network create ws-bench-net
docker run -d --network ws-bench-net --name ws-server <image>
docker run --rm --network ws-bench-net grafana/k6 run -e WS_URL=ws://ws-server:8080/ws /scripts/steady.js
```

**Decision**: ✅ ใช้ Docker bridge network ชื่อ `ws-bench-net`

---

### Q3: benchmark/run.sh รูปแบบ metrics
**คำถาม**: k6 output เป็น JSON หรือ text? parse อย่างไรใน bash?

**วิธี**: k6 `--out json=output.json` หรือ parse stdout

k6 stdout summary:
```
✓ connected successfully
checks.........................: 100.00% ✓ 6000 ✗ 0
ws_session_duration............: avg=59.99s
chat_msgs_sent.................: 6000
```

**Decision**: parse k6 stdout ด้วย `grep` + `awk` คล้าย projects เดิมในรีโป

---

### Q4: Rate Limit Implementation
**คำถาม**: ใช้ token bucket หรือ sliding window?

**ตัดสินใจ**: **Token Bucket** (1 bucket per connection, refill 10 tokens/sec)
- ง่ายต่อ implement ทั้ง 3 ภาษา
- Go: `time.Ticker` + counter per connection
- Rust: `tokio::time::Instant` + counter per connection
- Zig: `std.time.Instant` + counter per connection

---

## Acceptance Criteria
- [ ] Q1: ระบุ Zig WS approach + สร้าง `zig-ws-spike/` ถ้าเลือก manual implementation (spike 1-2h)
- [ ] Q2: ยืนยัน Docker network approach ใน `benchmark/run.sh` template
- [ ] Q3: เขียน bash parse snippet สำหรับ k6 output
- [ ] Q4: ยืนยัน token bucket approach และ interface ที่ทุกภาษาต้องทำ

## Tests Required
- [ ] Spike test: ถ้าเลือก Zig manual WS → ทำ minimal WS echo server ใน Zig ก่อน (proof of concept)

## Dependencies
- ไม่มี (ทำพร้อม 0.1 ได้)

## Files Affected
```
.breakdown/STATUS.md         # update decision และ unblock tasks
docs/decisions.md            # บันทึก ADR (Architecture Decision Record)
zig-ws-spike/ (ถ้าต้องการ) # PoC code ทิ้งไปหลัง verify
```

## Notes
- Task นี้ไม่มี deliverable code แต่สำคัญมาก — ถ้าข้ามไปเลือก approach ผิดต้องเสียเวลา
- Target: resolve ภายใน 1-2 ชั่วโมง ก่อนเริ่ม Epic 1-3
