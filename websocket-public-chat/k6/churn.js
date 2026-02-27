// Scenario 3: Churn
// 200 steady VUs — each VU loops: connect → join → wait 2s → leave → disconnect
// simulates rapid connection lifecycle (memory/goroutine leak detection)
import ws from 'k6/ws';
import { check } from 'k6';
import { Counter } from 'k6/metrics';

const connects = new Counter('churn_connects');
const disconnects = new Counter('churn_disconnects');
const wsErrors = new Counter('ws_errors');

const WS_URL = __ENV.WS_URL || 'ws://localhost:8080/ws';

export const options = {
  vus: 200,
  duration: '60s',
  thresholds: {
    'ws_errors': ['count==0'],
    'churn_connects': ['count>5000'],
  },
};

export default function () {
  const userId = `client-${__VU}`;
  let hadError = false;

  ws.connect(WS_URL, {}, function (socket) {
    socket.on('error', () => { hadError = true; wsErrors.add(1); });

    socket.on('open', () => {
      socket.send(JSON.stringify({ type: 'join', room: 'public', user: userId }));
      connects.add(1);
    });

    socket.on('message', (data) => {
      const msg = JSON.parse(data);
      if (msg.type === 'ping') {
        socket.send(JSON.stringify({ type: 'pong', ts: msg.ts }));
      }
    });

    // hold 2s จากนั้น leave
    socket.setTimeout(() => {
      socket.send(JSON.stringify({ type: 'leave', user: userId }));
      disconnects.add(1);
      socket.close();
    }, 2000);
  });

  check(hadError, { 'no ws error': (v) => v === false });
  // ไม่ sleep — loop ทันทีเพื่อสร้าง churn สูงสุด
}
