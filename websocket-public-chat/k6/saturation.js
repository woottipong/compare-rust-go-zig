// Scenario 4: Saturation Test
// Find the server's actual throughput ceiling by ramping VUs × 5 msg/s each:
//   Stage 1 (warm-up): 200 VUs × 5 msg/s = 1,000 msg/s theoretical
//   Stage 2 (push):    500 VUs × 5 msg/s = 2,500 msg/s theoretical
//   Stage 3 (stress):  1000 VUs × 5 msg/s = 5,000 msg/s theoretical
//
// The server's throughput (reported via server stats) plateaus when it saturates.
// Drop rate > 0 or ws_errors spike marks the practical ceiling.
import ws from 'k6/ws';
import { Counter } from 'k6/metrics';

const satMsgsSent = new Counter('sat_msgs_sent');
const wsErrors    = new Counter('ws_errors');

const WS_URL = __ENV.WS_URL || 'ws://localhost:8080/ws';

export const options = {
  scenarios: {
    ramp: {
      executor: 'ramping-vus',
      stages: [
        { duration: '10s', target: 200  },  // warm-up ramp
        { duration: '20s', target: 200  },  // baseline hold  — 200 VUs × 5 msg/s
        { duration: '10s', target: 500  },  // ramp to mid
        { duration: '20s', target: 500  },  // mid hold       — 500 VUs × 5 msg/s
        { duration: '10s', target: 1000 },  // ramp to stress
        { duration: '20s', target: 1000 },  // stress hold    — 1000 VUs × 5 msg/s
        { duration: '10s', target: 0    },  // ramp down
      ],
    },
  },
  // No hard thresholds — we want to observe saturation, not fail the test.
  // The server's drop_rate field reports when messages are rate-limited/dropped.
};

export default function () {
  const userId = `sat-${String(__VU).padStart(4, '0')}`;

  ws.connect(WS_URL, {}, function (socket) {
    socket.on('error', () => { wsErrors.add(1); });

    socket.on('open', () => {
      socket.send(JSON.stringify({ type: 'join', room: 'public', user: userId }));
    });

    socket.on('message', (data) => {
      try {
        const msg = JSON.parse(data);
        if (msg.type === 'ping') {
          socket.send(JSON.stringify({ type: 'pong', ts: msg.ts }));
        }
      } catch (_) { /* ignore parse errors */ }
    });

    // 5 messages per second — pushes well beyond the steady-state 1 msg/s
    socket.setInterval(() => {
      const text = `sat from ${userId}` + ' '.repeat(72);
      socket.send(JSON.stringify({ type: 'chat', room: 'public', user: userId, text }));
      satMsgsSent.add(1);
    }, 200);

    // Hold for 100s — longer than all stages so the VU stays alive throughout
    socket.setTimeout(() => {
      socket.send(JSON.stringify({ type: 'leave', user: userId }));
      socket.close();
    }, 100000);
  });
}
