// Scenario: Churn Soak — long-run connection lifecycle test
// 200 steady VUs — each VU loops: connect → join → wait 2s → leave → disconnect
// 180s duration — detects memory leaks and goroutine/resource accumulation over time
import ws from 'k6/ws';
import { check } from 'k6';
import { Counter } from 'k6/metrics';

const connects = new Counter('churn_connects');
const disconnects = new Counter('churn_disconnects');
const wsErrors = new Counter('ws_errors');

const WS_URL = __ENV.WS_URL || 'ws://localhost:8080/ws';

export const options = {
  vus: 200,
  duration: '180s',
  thresholds: {
    'ws_errors': ['count==0'],
    'churn_connects': ['count>16500'],  // 200 VUs × 180s / 2s per cycle = ~18000 expected
  },
};

export default function () {
  const userId = `client-${String(__VU).padStart(3, '0')}`;
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

    // hold 2s then leave — tight cycle maximises connection churn
    socket.setTimeout(() => {
      socket.send(JSON.stringify({ type: 'leave', user: userId }));
      disconnects.add(1);
      socket.close();
    }, 2000);
  });

  check(hadError, { 'no ws error': (v) => v === false });
  // no sleep — loop immediately to maximise churn rate
}
