// Scenario 1: Steady Load
// 100 VUs, 1 chat msg/sec each, 60s duration
import ws from 'k6/ws';
import { check } from 'k6';
import { Counter } from 'k6/metrics';

const chatMsgsSent = new Counter('chat_msgs_sent');
const chatMsgsReceived = new Counter('chat_msgs_received');
const wsErrors = new Counter('ws_errors');

const WS_URL = __ENV.WS_URL || 'ws://localhost:8080/ws';

export const options = {
  vus: 100,
  duration: '60s',
  thresholds: {
    'ws_session_duration': ['p(95)<65000'],  // 100 VUs × 60s session + headroom
    'chat_msgs_sent': ['count>5000'],
    'ws_errors': ['count==0'],
  },
};

export default function () {
  const userId = `client-${String(__VU).padStart(3, '0')}`;
  let hadError = false;

  ws.connect(WS_URL, {}, function (socket) {
    socket.on('error', () => { hadError = true; wsErrors.add(1); });

    socket.on('open', () => {
      socket.send(JSON.stringify({ type: 'join', room: 'public', user: userId }));
    });

    socket.on('message', (data) => {
      const msg = JSON.parse(data);
      if (msg.type === 'ping') {
        socket.send(JSON.stringify({ type: 'pong', ts: msg.ts }));
      } else if (msg.type === 'chat') {
        chatMsgsReceived.add(1);
      }
    });

    // send 1 msg/sec for the full duration; padding brings total JSON to ~128 bytes
    socket.setInterval(() => {
      const text = `hello from ${userId}` + ' '.repeat(67);
      socket.send(JSON.stringify({ type: 'chat', room: 'public', user: userId, text }));
      chatMsgsSent.add(1);
    }, 1000);

    socket.setTimeout(() => {
      socket.send(JSON.stringify({ type: 'leave', user: userId }));
      socket.close();
    }, 60000);
  });

  check(hadError, { 'no ws error': (v) => v === false });
}
