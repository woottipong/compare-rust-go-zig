# Workflow สำหรับ Claude-Assisted Development

ขั้นตอนมาตรฐานสำหรับทำงาน project ใหม่ร่วมกับ Claude ตั้งแต่ต้นจนจบ

---

## โครงสร้างไฟล์

```
project/
├── CLAUDE.md                  ← global instructions สำหรับ Claude (rules, workflow, conventions)
├── .prompts/
│   └── init.md                ← requirements, schema, architecture, use cases
└── .breakdown/
    ├── STATUS.md              ← ภาพรวม epic/task ทั้งหมด (kanban board)
    └── [task-name].md         ← รายละเอียดแต่ละ task พร้อม dependencies
```

---

## ขั้นตอน

### 1. เขียน Requirement ก่อนทุกอย่าง

สร้าง `.prompts/init.md` ที่มีอย่างน้อย:
- **Database schema** — table/field ที่จะใช้
- **Tech stack** — language, framework, external services
- **Use cases** — สิ่งที่ระบบต้องทำ

> ไม่ต้องสมบูรณ์ 100% แต่ต้องครอบคลุมสิ่งที่อยากได้ Claude จะถามส่วนที่ขาดหายไป

---

### 2. ตั้งค่า CLAUDE.md

ใส่ instruction ให้ Claude รู้จัก workflow นี้:

```markdown
# CLAUDE.md

## Workflow
- อ่าน .prompts/init.md ก่อนทำงานทุกครั้ง
- Maintain .breakdown/ เป็น kanban board เสมอ
- Update STATUS.md ทุกครั้งที่ task เปลี่ยน status
- แต่ละ task ต้องมี unittest เสมอ
- status [DONE] ได้ก็ต่อเมื่อ test ผ่านแล้วเท่านั้น
- Track dependencies ระหว่าง task ทุกครั้งที่สร้างหรือแก้ task
- สร้าง .claude/CLAUDE.md แยกสำหรับแต่ละ module เพื่อ scope context
```

---

### 3. Breakdown ก่อน ห้ามเขียนโค้ด

Prompt:
```
แตก task จาก .prompts/init.md ไปใส่ใน .breakdown/
ยังไม่ต้องเขียนโค้ด ให้ใช้ planning และค้นหาข้อมูลที่จำเป็นก่อน
```

Claude จะสร้าง:
- `.breakdown/STATUS.md` — ตาราง epic/task พร้อม status
- `.breakdown/<task-name>.md` — รายละเอียดแต่ละ task

**Task card format:**
```markdown
# Task 1.1: ชื่อ task

## Status
[TODO] / [IN PROGRESS] / [DONE] / [BLOCKED]

## Description
อธิบายว่าต้องทำอะไร

## Acceptance Criteria
- [ ] เงื่อนไขที่ต้องผ่าน
- [ ] เงื่อนไขที่ต้องผ่าน

## Tests Required
- unit test สำหรับ X
- integration test สำหรับ Y

## Dependencies
- ต้องทำ Task 1.0 ก่อน
- ใช้ output จาก Task 0.1

## Files Affected
- src/module/file.go
- tests/module/file_test.go
```

---

### 4. Review และ Iterate

คุยกับ Claude หลายรอบก่อน approve:
- design choice ที่ยังไม่แน่ใจ
- tech stack ที่มี trade-off
- edge cases ที่อาจพลาด

จนพอใจกับ plan แล้วค่อย approve ให้เริ่มเขียนโค้ด

---

### 5. ทำทีละ Epic หรือทีละ Task

ตัวอย่าง prompt:
```
ทำ epic 1
```
```
ทำ task 1.1-1.3
```
```
what's your suggested first task?
```

Claude จะทำทีละก้อน อัปเดต `.breakdown/` ทุกครั้งที่ task เสร็จ

---

### 6. ตรวจสอบและ Adjust

หลังแต่ละ task Claude จะ:
- อัปเดต `STATUS.md` — เปลี่ยน status เป็น [DONE]
- แจ้ง files ที่ถูก affected
- แจ้ง dependencies ที่อาจกระทบ

ถ้าไม่ถูกใจ:
```
spin task 1.2 ใหม่และ update dependencies ที่กระทบ
```

---

## กฎสำคัญใน CLAUDE.md

```markdown
## Rules

### Testing
- แต่ละ task ต้องมี unittest เสมอ
- status [DONE] ได้ก็ต่อเมื่อ test ผ่านแล้วเท่านั้น
- ห้าม skip test แม้จะ "simple" task

### Breakdown
- สร้าง .claude/CLAUDE.md แยกต่างหากสำหรับแต่ละ module เพื่อ scope context
- Track dependencies ระหว่าง task ทุกครั้งที่สร้างหรือแก้ task
- Task ที่ blocked ต้องระบุ blocker ชัดเจนใน task card

### Code
- ห้ามเขียนโค้ดก่อนที่ task จะอยู่ใน .breakdown/
- ทำทีละ task อย่าข้ามขั้นตอน
- แต่ละ commit ต้องตรงกับ task เดียว
```

---

## STATUS.md Format

```markdown
# Project Status

## Epic 1: ชื่อ epic
| Task | Description | Status | Depends On |
|------|-------------|--------|------------|
| 1.1 | สร้าง database schema | [DONE] | — |
| 1.2 | สร้าง repository layer | [IN PROGRESS] | 1.1 |
| 1.3 | สร้าง service layer | [TODO] | 1.2 |
| 1.4 | สร้าง API handler | [TODO] | 1.3 |

## Epic 2: ชื่อ epic
| Task | Description | Status | Depends On |
|------|-------------|--------|------------|
| 2.1 | ... | [TODO] | 1.4 |

## Legend
- [TODO] — ยังไม่เริ่ม
- [IN PROGRESS] — กำลังทำ
- [DONE] — เสร็จแล้ว test ผ่าน
- [BLOCKED] — รอ dependency
```

---

## ตัวอย่าง .prompts/init.md

```markdown
# Project: User Authentication Service

## Tech Stack
- Language: Go 1.25
- Framework: Fiber
- Database: PostgreSQL 16
- Cache: Redis 7
- Auth: JWT (access 15m / refresh 7d)

## Database Schema

### users
| Column | Type | Notes |
|--------|------|-------|
| id | uuid | PK |
| email | varchar(255) | unique |
| password_hash | varchar | bcrypt |
| created_at | timestamptz | |

### refresh_tokens
| Column | Type | Notes |
|--------|------|-------|
| id | uuid | PK |
| user_id | uuid | FK users.id |
| token_hash | varchar | |
| expires_at | timestamptz | |
| revoked | boolean | default false |

## Use Cases
1. Register ด้วย email/password
2. Login → ได้ access token + refresh token
3. Refresh access token ด้วย refresh token
4. Logout → revoke refresh token
5. Get current user profile

## Non-goals v1
- OAuth / Social login
- 2FA / MFA
- Email verification
```

---

## ข้อดีของ Workflow นี้

| ปัญหาเดิม | วิธีแก้ใน Workflow นี้ |
|-----------|----------------------|
| Claude เขียนโค้ดแล้วต้องแก้ทั้งหมดเพราะ design ผิด | Breakdown + review ก่อน ไม่เขียนโค้ดจนกว่าจะ approve |
| ไม่รู้ว่า Claude ทำถึงไหนแล้ว | STATUS.md เป็น single source of truth |
| Task ขาด dependency ทำให้ build พัง | Track dependencies ชัดเจนทุก task card |
| ไม่มี test → bug เยอะ | Test required ก่อน [DONE] ทุกครั้ง |
| Context window ล้น ทำให้ Claude ลืม | .claude/CLAUDE.md แยก module → scope context |
