package main

import (
	"testing"
	"time"
)

func TestRateLimit(t *testing.T) {
	stats := newStats()
	hub := newHub(stats)
	go hub.run()
	time.Sleep(10 * time.Millisecond)

	c := makeTestClient(hub)
	hub.register <- c
	time.Sleep(10 * time.Millisecond)

	// Exhaust the bucket: first 10 should pass, rest should be denied
	passed := 0
	dropped := 0
	for i := 0; i < 20; i++ {
		if c.allow() {
			passed++
		} else {
			dropped++
		}
	}

	if passed != 10 {
		t.Errorf("expected 10 messages to pass, got %d", passed)
	}
	if dropped != 10 {
		t.Errorf("expected 10 messages to be dropped, got %d", dropped)
	}
}

func TestRateLimitRefill(t *testing.T) {
	stats := newStats()
	hub := newHub(stats)
	go hub.run()
	time.Sleep(10 * time.Millisecond)

	c := makeTestClient(hub)
	hub.register <- c
	time.Sleep(10 * time.Millisecond)

	// Drain the bucket
	for i := 0; i < tokenBucketMax; i++ {
		c.allow()
	}
	if c.allow() {
		t.Fatal("bucket should be empty after draining")
	}

	// Force lastRefill to 1 second ago → should refill 10 tokens
	c.lastRefill = time.Now().Add(-1 * time.Second)

	if !c.allow() {
		t.Fatal("expected token after 1s refill")
	}
}

func TestClientTokenInitialState(t *testing.T) {
	stats := newStats()
	hub := newHub(stats)
	c := makeTestClient(hub)

	if c.tokens != tokenBucketMax {
		t.Errorf("expected initial tokens=%d, got %d", tokenBucketMax, c.tokens)
	}
}
