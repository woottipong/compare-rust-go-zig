# 🚀 Plan 2: Advanced Benchmark Projects

## 📋 โปรเจกต์ขั้นสูงที่เสนอ

### 1. WebSocket Public Chat Benchmark
**Complexity**: Medium-High | **Duration**: 2-3 weeks

#### 🧭 Benchmark Profiles (ลำดับการทำ)

**Profile B (Primary): Minimal/Low-level parity**
- เป้าหมาย: เทียบ runtime/network behavior โดยลดผลจาก framework abstraction
- ใช้เป็น baseline หลักของโปรเจกต์นี้

**Profile A (Secondary): Framework/Production profile**
- เป้าหมาย: เทียบผลลัพธ์ในแนวทางที่ใกล้ production
- ทำหลัง Profile B เสร็จ เพื่อดู delta จาก framework

#### 🎯 Use Case
Real-time public chat room ที่เน้น benchmark แบบเทียบกันได้จริง:
- WebSocket connection lifecycle (connect, join, ping/pong, disconnect)
- Public room broadcast (ข้อความเดียว กระจายถึงทุก client ในห้อง)
- Per-client rate limiting
- Load under steady, burst, churn patterns

#### ✅ Scope v1 (MVP-First)
- Single room
- Text-only message
- Ping/Pong keepalive (30s)
- Basic per-client rate limit (10 msg/sec)
- ไม่รวม auth/persistence/file upload ในรอบแรก
- ใช้ **Profile B เป็นตัวหลักก่อน**

#### 🚫 Non-goals v1
- JWT/AuthN/AuthZ
- Message history persistence
- File/image transfer
- Multi-region / distributed room state

#### 🔧 Technical Focus
| Profile | Go | Rust | Zig |
|---------|----|------|-----|
| **B (Primary, Minimal)** | net/http + gorilla/websocket | tokio-tungstenite (minimal stack) | std.net + minimal WS implementation |
| **A (Secondary, Framework)** | GoFiber + websocket | Axum + tokio-tungstenite | Zap (หรือ framework ที่เทียบเท่า) |

#### ✅ Execution Order (บังคับใช้ในแผน)
1. Implement + benchmark **Profile B** ให้ครบ 3 ภาษา
2. Freeze benchmark contract (schema/payload/scenarios)
3. Implement **Profile A** โดยใช้ contract เดิมทุกข้อ
4. สรุปผล B vs A แยกชัดเจนใน README/results

#### ⚖️ Fairness Rules (ต้องเท่ากันทุกภาษา)
1. Message schema เดียวกัน (JSON): `join`, `chat`, `ping`, `pong`, `leave`
2. Payload ขนาดเท่ากัน (เช่น 128 bytes ต่อ `chat` message)
3. Client behavior เท่ากัน (send rate, reconnect policy, timeout)
4. Benchmark duration เท่ากัน (warm-up + measured)
5. Resource limit เท่ากัน (CPU/memory/container settings)
6. Output metrics format เดียวกันตามมาตรฐาน repo

#### 📊 Benchmark Scenarios
```text
Scenario A (Steady): 100 clients, 1 msg/sec, 5 min
Scenario B (Burst): 1000 clients connect within 10 sec
Scenario C (Churn): connect/disconnect loop with constant active clients
```

#### 📈 Metrics (Primary/Secondary)
Primary:
- Throughput (messages/sec)
- End-to-end latency avg + p95 + p99 (ms)
- Connection success rate (%), message drop rate (%)

Secondary:
- Memory per active connection
- CPU usage under peak load
- Reconnect recovery time

#### 🎯 Success Metrics
- >= 10,000 msg/sec throughput (burst phase)
- p95 latency < 50ms (steady phase)
- < 100MB memory for 1000 active connections (language-specific target)
- < 1% failed connections/messages

#### 🧪 Standard Statistics Output (ทุกภาษา)
```text
--- Statistics ---
Total messages: <N>
Processing time: <X.XXX>s
Average latency: <X.XXX>ms
Throughput: <X.XX> messages/sec
```

#### 🛠️ Milestones + Exit Criteria
Milestone 1: **Profile B** Basic WS Echo/Broadcast
- Exit: 100 clients steady test ผ่านครบ 3 ภาษา (minimal stack)

Milestone 2: **Profile B** Rate Limit + Ping/Pong
- Exit: disconnect timeout ทำงานถูกต้อง, no dead connections leak

Milestone 3: **Profile B** Burst/Churn Harness
- Exit: รัน scenario B/C ได้ครบ + เก็บ metrics ได้เท่ากัน

Milestone 4: **Profile A** Framework parity run
- Exit: รันครบ scenario เดิม + report เปรียบเทียบ Profile B vs A

Milestone 5: Multi-room (optional v2)
- Exit: 100 rooms x 10 clients พร้อม message isolation ถูกต้อง

---

### 2. Distributed Rate Limiter Service Benchmark
**Complexity**: Medium-High | **Duration**: 2-3 weeks

#### 🎯 Use Case
บริการ rate limiter กลางที่ใช้งานได้จริงกับ API/Chat:
```
Client/API Gateway → Rate Limiter Service → Redis/Local State → Allow/Deny
```

#### ✅ Scope v1 (MVP-First)
- รองรับ policy: per-user, per-IP, per-route
- Sliding Window และ Token Bucket
- Redis-backed mode + in-memory fallback mode
- Decision API: `check` / `check_and_consume`

#### 🚫 Non-goals v1
- Global multi-region consistency
- Dynamic policy UI/dashboard
- Machine-learning based abuse detection

#### 🔧 Technical Focus
| Language | Stack | Key Challenge |
|----------|-------|---------------|
| Go | GoFiber + redis + goroutines | Lock/contention under high QPS |
| Rust | Axum + redis-rs + tokio | Predictable latency at high concurrency |
| Zig | std.net + Redis client/manual | Correctness + efficient state handling |

#### ⚖️ Fairness Rules (ต้องเท่ากันทุกภาษา)
1. Policy set เดียวกัน (rate/window/burst)
2. Key distribution เดียวกัน (hot keys + long tail)
3. Redis config เดียวกัน (maxmemory/eviction)
4. Timeout/retry เดียวกัน
5. Allow/Deny semantics เท่ากันทุก implementation

#### 📊 Benchmark Scenarios
```text
Scenario A (Normal): 50K checks/sec, mixed keys
Scenario B (Hot Key): 80% requests ตกที่ key เดียว
Scenario C (Redis Degrade): latency spike + partial timeout
```

#### 📈 Metrics (Primary/Secondary)
Primary:
- Checks/sec
- Decision latency avg/p95/p99
- Accuracy (false allow / false deny)

Secondary:
- Redis RTT contribution
- Fallback hit ratio
- CPU/RSS memory

#### 🎯 Success Metrics
- >= 50K checks/sec sustained
- p95 decision latency < 20ms
- false allow/deny <= 0.1%
- degrade mode ยังให้บริการได้โดย error rate < 2%

#### 🧪 Standard Statistics Output (ทุกภาษา)
```text
--- Statistics ---
Total checks: <N>
Processing time: <X.XXX>s
Average latency: <X.XXX>ms
Throughput: <X.XX> checks/sec
```

#### 🛠️ Milestones + Exit Criteria
Milestone 1: In-memory limiter + API endpoint
- Exit: normal scenario ผ่านครบ 3 ภาษา

Milestone 2: Redis-backed limiter + policy parity
- Exit: allow/deny results ตรงกันทุกภาษาใน test vectors

Milestone 3: Degrade/fallback + hot-key optimization
- Exit: scenario B/C ผ่านพร้อม metrics accuracy

---

## 🎪 Progressive Complexity Path

### Phase 1: Foundation (Week 1-2)
```text
✅ Basic service implementation
✅ Simple benchmark harness
✅ Core functionality validation
✅ Docker orchestration setup
```

### Phase 2: Production Features (Week 3-4)
```text
✅ Circuit breakers & retries
✅ Monitoring & metrics
✅ Load generation tools
✅ Failure scenario testing
```

### Phase 3: Enterprise Grade (Week 5-8)
```text
✅ Service mesh integration
✅ Distributed tracing
✅ Configuration management
✅ Auto-scaling simulation
```

---

## 📊 Comparison Matrix

| Aspect | WebSocket Chat | Distributed Rate Limiter |
|--------|----------------|--------------------------|
| **Learning Value** | Real-time communication | Policy + abuse protection |
| **Implementation** | Medium | Medium-High |
| **Infrastructure** | Docker Compose | Redis + API |
| **Zig Challenge** | WS protocol handling | state + redis consistency |
| **Production Relevance** | High | Very High |
| **Time Investment** | 2-3 weeks | 2-3 weeks |

---

## 🎯 Recommendation

### **For Maximum Learning**
```text
→ WebSocket Public Chat
```
- ครอบคลุม real-time connection lifecycle, broadcast, และ rate limiting
- เหมาะกับการต่อยอดไประบบ chat/gateway ใน production
- เทียบ runtime/network behavior ได้ชัดใน Profile B

### **For Balanced Complexity**
```text
→ Distributed Rate Limiter Service
```
- ใช้งานจริงกับ API Gateway/Chat/Anti-abuse ได้ทันที
- เห็นผลของ algorithm (sliding window/token bucket) ชัด
- scope เหมาะกับรอบ implement สั้น

### **For Data Processing Focus**
```text
→ (พักไว้ก่อน) Event-Driven Log Pipeline
```
- ค่อยเพิ่มในเฟสถัดไปเมื่อสองโปรเจกต์แรกเสร็จ

---

## 🚀 Getting Started

### Step 1: Choose Project
```text
Consider:
- Team size and experience
- Available time commitment
- Learning objectives
- Infrastructure requirements
```

### Step 2: Define MVP
```text
Minimum Viable Product:
- Core functionality working
- Basic benchmark running
- 3 languages implemented
- Docker-based deployment
```

### Step 3: Plan Iterations
```text
Iteration 1: Basic implementation
Iteration 2: Performance optimization  
Iteration 3: Production features
Iteration 4: Advanced scenarios
```

---

## 💡 Success Tips

### Technical Tips
```text
1. Start with existing libraries (don't reinvent)
2. Use Docker Compose for orchestration
3. Implement comprehensive logging
4. Monitor resource usage continuously
5. Test failure scenarios early
```

### Project Management Tips
```text
1. Define clear success metrics
2. Weekly progress checkpoints
3. Document architectural decisions
4. Maintain consistent coding standards
5. Plan for Zig ecosystem limitations
```

---

## 🎉 Expected Outcomes

### Technical Skills
```text
✅ Distributed system design
✅ Performance optimization
✅ Failure handling patterns
✅ Monitoring & observability
✅ Container orchestration
```

### Language Insights
```text
✅ Go: Rapid development + rich ecosystem
✅ Rust: Type safety + zero-cost abstractions
✅ Zig: Manual control + minimal dependencies
```

### Production Readiness
```text
✅ Real-world system architecture
✅ Scalability patterns
✅ Operational best practices
✅ Performance benchmarking methodology
```

---

**เลือกโปรเจกต์ที่ตรงกับเป้าหมายและความพร้อมของทีม แล้วจะได้ประสบการณ์การเรียนรู้ที่ลึกซึ้งและน่าประทับใจ** 🚀
