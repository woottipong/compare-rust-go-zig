// Scenario: Steady Soak — production readiness test
// 100 VUs, 1 chat msg/sec each, 300s duration
// KPIs: memory drift, throughput stability, error accumulation
import ws from 'k6/ws';
import { check } from 'k6';
import { Counter, Trend } from 'k6/metrics';

const chatMsgsSent = new Counter('chat_msgs_sent');
const chatMsgsReceived = new Counter('chat_msgs_received');
const wsErrors = new Counter('ws_errors');
const msgDeliveryLatency = new Trend('msg_delivery_latency', true);

const WS_URL = __ENV.WS_URL || 'ws://localhost:8080/ws';

export const options = {
  vus: 100,
  duration: '300s',
  thresholds: {
    'ws_session_duration': ['p(95)<305000'],  // 300s session + 5s headroom
    'chat_msgs_sent': ['count>25000'],         // 100 VUs × ~250s effective × 1 msg/s
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
        if (msg.text) {
          const match = msg.text.match(/ts:(\d+)/);
          if (match) {
            const sendTs = parseInt(match[1]);
            const latency = Date.now() - sendTs;
            if (latency >= 0 && latency < 60000) {
              msgDeliveryLatency.add(latency);
            }
          }
        }
        chatMsgsReceived.add(1);
      }
    });

    // send 1 msg/sec for the full duration; padding brings total JSON to ~128 bytes
    socket.setInterval(() => {
      const sendTs = Date.now();
      const text = `hello from ${userId}|ts:${sendTs}` + ' '.repeat(40);
      socket.send(JSON.stringify({ type: 'chat', room: 'public', user: userId, text }));
      chatMsgsSent.add(1);
    }, 1000);

    socket.setTimeout(() => {
      socket.send(JSON.stringify({ type: 'leave', user: userId }));
      socket.close();
    }, 300000);
  });

  check(hadError, { 'no ws error': (v) => v === false });
}
