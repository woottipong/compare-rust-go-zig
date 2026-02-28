# Task 0.4: Resolve Open Questions

## Status
[DONE]

## Priority
— (build task)

## Description
ค้นหาและตัดสินใจประเด็นที่กระทบ architecture ก่อนเขียนโค้ด — ถ้า resolve ผิดต้อง refactor ทั้ง epic ดังนั้นต้องทำก่อนเริ่ม Epic 1-3

## Acceptance Criteria
- [x] Q1 resolved: Zig WS library → ใช้ **zap v0.11.0** (facil.io pub/sub)
- [x] Q2 resolved: Docker network → ใช้ bridge network `ws-bench-net`
- [x] Q3 resolved: k6 output parsing → parse stdout ด้วย `grep` + `awk`
- [x] Q4 resolved: Rate limit → **Token Bucket** (10 tokens/sec per connection)
- [x] บันทึก decisions ใน `docs/decisions.md` (ADR)
- [x] อัปเดต STATUS.md unblock tasks ที่รอ

## Tests Required
- [x] PoC: Zig WS echo server (`wscat -c ws://localhost:8080` → echo กลับ ไม่ error)

## Dependencies
- ไม่มี (ทำพร้อม 0.1 ได้)

## Files Affected
```
.breakdown/STATUS.md       # update decisions + unblock tasks
docs/decisions.md          # Architecture Decision Records
```

## Implementation Notes

### Decision Log

| # | คำถาม | Decision | เหตุผล |
|---|-------|----------|--------|
| Q1 | Zig WS library | `zap` v0.11.0 | Zig 0.15.1 compatible, มี WS via facil.io pub/sub |
| Q2 | Docker network | Bridge `ws-bench-net` | k6 container คุยกับ server container ผ่าน service name |
| Q3 | k6 output format | Parse stdout | เรียบง่าย เหมือน projects อื่นในรีโป |
| Q4 | Rate limit | Token Bucket | ง่ายต่อ implement ทั้ง 3 ภาษา, predictable behavior |

### Rate Limit Interface (ทุกภาษาต้อง implement)
```
tokens    : u32 = 10  (max capacity)
refill    : +1 token ทุก 100ms (หรือ check elapsed time per message)
on_exceed : drop message (log, ไม่ disconnect)
```

> **Note**: Task นี้ไม่มี deliverable code แต่สำคัญมาก — ถ้าข้ามไปแล้วเลือก approach ผิดจะเสียเวลา refactor ทั้ง epic
