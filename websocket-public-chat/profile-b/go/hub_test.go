package main

import (
	"testing"
	"time"
)

// makeTestClient creates a minimal client for hub testing (no real WS conn).
func makeTestClient(hub *Hub) *Client {
	return &Client{
		hub:        hub,
		send:       make(chan []byte, sendBufSize),
		tokens:     tokenBucketMax,
		lastRefill: time.Now(),
	}
}

func TestHubRegisterUnregister(t *testing.T) {
	stats := newStats()
	hub := newHub(stats)
	go hub.run()
	time.Sleep(10 * time.Millisecond) // let hub goroutine start

	// Register 5 clients
	clients := make([]*Client, 5)
	for i := range clients {
		clients[i] = makeTestClient(hub)
		hub.register <- clients[i]
	}
	time.Sleep(20 * time.Millisecond)

	if got := hub.clientCount(); got != 5 {
		t.Fatalf("expected 5 clients after register, got %d", got)
	}

	// Unregister 2
	hub.unregister <- clients[0]
	hub.unregister <- clients[1]
	time.Sleep(20 * time.Millisecond)

	if got := hub.clientCount(); got != 3 {
		t.Fatalf("expected 3 clients after unregister, got %d", got)
	}
}

func TestBroadcastToOthers(t *testing.T) {
	stats := newStats()
	hub := newHub(stats)
	go hub.run()
	time.Sleep(10 * time.Millisecond)

	c1 := makeTestClient(hub)
	c2 := makeTestClient(hub)
	c3 := makeTestClient(hub)

	hub.register <- c1
	hub.register <- c2
	hub.register <- c3
	time.Sleep(20 * time.Millisecond)

	msg := []byte(`{"type":"chat","user":"c1","text":"hello"}`)
	hub.broadcastExcept(c1, msg)

	// c2 and c3 should receive
	timeout := time.After(100 * time.Millisecond)
	for _, c := range []*Client{c2, c3} {
		select {
		case got := <-c.send:
			if string(got) != string(msg) {
				t.Errorf("expected %q, got %q", msg, got)
			}
		case <-timeout:
			t.Fatal("timed out waiting for broadcast message")
		}
	}

	// c1 should NOT receive (channel should be empty)
	select {
	case unexpected := <-c1.send:
		t.Errorf("c1 should not receive its own broadcast, got %q", unexpected)
	case <-time.After(20 * time.Millisecond):
		// expected: no message
	}
}
