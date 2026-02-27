// Scenario 2: Burst Connect
// Ramp 0 → 1000 VUs in 10s, hold 5s, ramp down 5s
import ws from 'k6/ws';
import { check } from 'k6';
import { Counter } from 'k6/metrics';

const chatMsgsSent = new Counter('chat_msgs_sent');
const wsErrors = new Counter('ws_errors');

const WS_URL = __ENV.WS_URL || 'ws://localhost:8080/ws';

export const options = {
  scenarios: {
    burst: {
      executor: 'ramping-vus',
      stages: [
        { duration: '10s', target: 1000 }, // ramp up
        { duration: '5s',  target: 1000 }, // hold
        { duration: '5s',  target: 0    }, // ramp down
      ],
    },
  },
  thresholds: {
    'ws_errors': ['count==0'],
    'ws_session_duration': ['p(95)<16000'],  // 10s ramp + 5s hold + headroom
  },
};

export default function () {
  const userId = `client-${String(__VU).padStart(3, '0')}`;
  let hadError = false;

  ws.connect(WS_URL, {}, function (socket) {
    socket.on('error', () => { hadError = true; wsErrors.add(1); });

    socket.on('open', () => {
      socket.send(JSON.stringify({ type: 'join', room: 'public', user: userId }));
      // send 1 message then hold until timeout; padding brings total JSON to ~128 bytes
      const text = `burst from ${userId}` + ' '.repeat(67);
      socket.send(JSON.stringify({ type: 'chat', room: 'public', user: userId, text }));
      chatMsgsSent.add(1);
    });

    socket.on('message', (data) => {
      const msg = JSON.parse(data);
      if (msg.type === 'ping') {
        socket.send(JSON.stringify({ type: 'pong', ts: msg.ts }));
      }
    });

    socket.setTimeout(() => {
      socket.send(JSON.stringify({ type: 'leave', user: userId }));
      socket.close();
    }, 15000);
  });

  check(hadError, { 'no ws error': (v) => v === false });
}
