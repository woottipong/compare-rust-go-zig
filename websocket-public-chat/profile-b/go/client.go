package main

import (
	"encoding/json"
	"log"
	"net/http"
	"time"

	"github.com/gorilla/websocket"
)

const (
	writeWait      = 10 * time.Second
	pongWait       = 60 * time.Second
	pingPeriod     = PingIntervalSec * time.Second
	maxMessageSize = 512
	sendBufSize    = 64
	tokenBucketMax = RateLimitMsgPerSec
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  512,
	WriteBufferSize: 512,
	CheckOrigin:     func(r *http.Request) bool { return true },
}

// Client represents a single WebSocket connection.
type Client struct {
	hub        *Hub
	conn       *websocket.Conn
	send       chan []byte
	user       string
	tokens     int
	lastRefill time.Time
}

// allow checks the token bucket and returns true if message may proceed.
// Uses integer millisecond arithmetic to avoid float truncation: elapsed < 100ms
// with Seconds() would yield 0 refill even when some tokens are due.
func (c *Client) allow() bool {
	now := time.Now()
	elapsedMs := now.Sub(c.lastRefill).Milliseconds()
	refill := int(elapsedMs) * RateLimitMsgPerSec / 1000
	if refill > 0 {
		c.tokens += refill
		if c.tokens > tokenBucketMax {
			c.tokens = tokenBucketMax
		}
		c.lastRefill = now
	}
	if c.tokens <= 0 {
		return false
	}
	c.tokens--
	return true
}

// readPump pumps messages from the WebSocket connection to the hub.
// One goroutine per client.
func (c *Client) readPump() {
	defer func() {
		c.hub.unregister <- c
		c.conn.Close()
	}()

	c.conn.SetReadLimit(maxMessageSize)
	c.conn.SetReadDeadline(time.Now().Add(pongWait))
	c.conn.SetPongHandler(func(string) error {
		c.conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})

	for {
		_, raw, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("client %s error: %v", c.user, err)
			}
			break
		}

		var msg Message
		if err := json.Unmarshal(raw, &msg); err != nil {
			continue // ignore malformed JSON
		}

		switch msg.Type {
		case MsgJoin:
			c.user = msg.User

		case MsgChat:
			if !c.allow() {
				c.hub.stats.addDropped()
				log.Printf("rate limit: dropped message from %s", c.user)
				continue
			}
			c.hub.stats.addMessage()
			c.hub.broadcastExcept(c, raw)

		case MsgPong:
			// handled by SetPongHandler above

		case MsgLeave:
			return
		}
	}
}

// writePump pumps messages from the hub to the WebSocket connection.
// One goroutine per client. gorilla/websocket requires single writer.
func (c *Client) writePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()

	for {
		select {
		case message, ok := <-c.send:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			if err := c.conn.WriteMessage(websocket.TextMessage, message); err != nil {
				return
			}

		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			ts := time.Now().UnixMilli()
			ping, _ := json.Marshal(Message{Type: MsgPing, Ts: ts})
			if err := c.conn.WriteMessage(websocket.TextMessage, ping); err != nil {
				return
			}
		}
	}
}

// serveWs handles WebSocket upgrade requests.
func serveWs(hub *Hub, w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("upgrade error: %v", err)
		return
	}

	client := &Client{
		hub:        hub,
		conn:       conn,
		send:       make(chan []byte, sendBufSize),
		tokens:     tokenBucketMax,
		lastRefill: time.Now(),
	}
	hub.register <- client

	go client.writePump()
	go client.readPump()
}
