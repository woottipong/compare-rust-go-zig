# Task 8.3: k6 — เพิ่ม E2E Latency Metric ใน steady.js

## Status
[DONE]

## Description
ปัจจุบัน k6 วัดแค่:
- `ws_connecting` — connection establishment time
- `chat_msgs_sent` / `chat_msgs_received` — count

แต่ไม่มี **message delivery latency** (เวลาตั้งแต่ sender ส่ง → receiver ได้รับ)

เพิ่ม custom metric ใน `steady.js`:
- ใส่ timestamp ใน chat message `text` field
- receiver เมื่อได้รับ message ให้คำนวณ `now - msg.ts` = delivery latency
- บันทึกเป็น k6 Trend metric → ได้ p50/p95/p99 ของ delivery latency

## Acceptance Criteria
- [x] k6 output มี `msg_delivery_latency` metric ใหม่
- [x] แสดง p50, p95, p99 ของ delivery latency
- [x] ไม่กระทบ scenario อื่น (burst, churn, saturation)
- [x] Latency วัดเป็น milliseconds

## Tests Required
- manual: รัน steady scenario ต่อ Go server → verify `msg_delivery_latency` ปรากฏใน output

## Dependencies
- ไม่มี — standalone k6 change

## Files Affected
- `k6/steady.js`

## Implementation Notes

### เพิ่ม Trend metric
```javascript
import { Trend } from 'k6/metrics';

const msgDeliveryLatency = new Trend('msg_delivery_latency', true);
```

### Sender: ใส่ timestamp ใน text
```javascript
socket.setInterval(() => {
    const sendTs = Date.now();
    const text = `hello from ${userId}|ts:${sendTs}` + ' '.repeat(40);
    socket.send(JSON.stringify({
        type: 'chat', room: 'public', user: userId, text,
    }));
    chatMsgsSent.add(1);
}, 1000);
```

### Receiver: วัด latency
```javascript
socket.on('message', (data) => {
    const msg = JSON.parse(data);
    if (msg.type === 'chat' && msg.text) {
        const match = msg.text.match(/ts:(\d+)/);
        if (match) {
            const sendTs = parseInt(match[1]);
            const latency = Date.now() - sendTs;
            if (latency >= 0 && latency < 60000) {
                msgDeliveryLatency.add(latency);
            }
        }
        chatMsgsReceived.add(1);
    } else if (msg.type === 'ping') {
        socket.send(JSON.stringify({ type: 'pong', ts: msg.ts }));
    }
});
```

### หมายเหตุ
- Latency ข้ามคนอาจมี clock skew ถ้า k6 + server อยู่คนละ container
- แต่ k6 คือ sender+receiver ในตัวเดียว → clock เดียวกัน ✓
- ข้อจำกัด: วัดได้แค่ loopback latency (sender → server → receiver ที่เป็น k6 client อีกตัว)
