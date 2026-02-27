# Task 0.3: k6 Load-Test Scripts (3 Scenarios)

## Status
[TODO]

## Description
เขียน k6 JavaScript scripts สำหรับ 3 scenarios โดยใช้ `k6/ws` API เพื่อทดสอบ WebSocket server

## Acceptance Criteria
- [ ] `k6/steady.js`: 100 VUs, 1 msg/sec ต่อ VU, duration 60s
- [ ] `k6/burst.js`: ramp up 1000 VUs ภายใน 10s, hold 5s, ramp down
- [ ] `k6/churn.js`: 200 VUs constant, ทุก iteration = connect → join → wait 2s → leave → disconnect
- [ ] ทุก script collect metrics: `ws_msgs_sent`, `ws_msgs_received`, `ws_session_duration`, `checks`
- [ ] ทุก script รับ env var `WS_URL` (default: `ws://localhost:8080/ws`)
- [ ] ทุก script export JSON summary ที่ parse ได้ใน bash
- [ ] `k6/Dockerfile` — image พร้อมรัน

## Tests Required
- [ ] รัน `k6 run --vus 1 --duration 5s k6/steady.js` กับ server จำลอง (echo server) — ไม่ error
- [ ] verify ว่า output มี `checks` metric ครบ

## Dependencies
- Task 0.1, 0.2

## Files Affected
```
k6/steady.js
k6/burst.js
k6/churn.js
k6/Dockerfile
```

## k6 Script Template (steady.js)

```javascript
import ws from 'k6/ws';
import { check, sleep } from 'k6';
import { Counter } from 'k6/metrics';

const msgsSent = new Counter('chat_msgs_sent');
const msgsReceived = new Counter('chat_msgs_received');

const WS_URL = __ENV.WS_URL || 'ws://localhost:8080/ws';
const USER_PREFIX = 'client';

export const options = {
  vus: 100,
  duration: '60s',
  thresholds: {
    'ws_session_duration': ['p(95)<50'],   // p95 < 50ms
    'chat_msgs_sent': ['count>5000'],
  },
};

export default function () {
  const userId = `${USER_PREFIX}-${__VU}`;

  const res = ws.connect(WS_URL, {}, function (socket) {
    socket.on('open', () => {
      socket.send(JSON.stringify({ type: 'join', room: 'public', user: userId }));
    });

    socket.on('message', (data) => {
      const msg = JSON.parse(data);
      if (msg.type === 'ping') {
        socket.send(JSON.stringify({ type: 'pong', ts: msg.ts }));
      } else if (msg.type === 'chat') {
        msgsReceived.add(1);
      }
    });

    // ส่ง 1 msg/sec ตลอด duration
    socket.setInterval(() => {
      const text = 'hello from ' + userId + ' '.repeat(60); // ~128 bytes
      socket.send(JSON.stringify({ type: 'chat', user: userId, text }));
      msgsSent.add(1);
    }, 1000);

    socket.setTimeout(() => {
      socket.send(JSON.stringify({ type: 'leave', user: userId }));
      socket.close();
    }, 60000);
  });

  check(res, { 'connected successfully': (r) => r && r.status === 101 });
}
```

## Notes
- k6 Docker image: `grafana/k6:latest`
- รันด้วย: `docker run --rm --network <net> -e WS_URL=ws://server:8080/ws grafana/k6 run /scripts/steady.js`
- mount scripts: `-v "$K6_DIR":/scripts:ro`
