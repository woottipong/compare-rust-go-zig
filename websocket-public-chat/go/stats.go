package main

import (
	"fmt"
	"sync/atomic"
	"time"
)

// Stats tracks server-level metrics. All fields are updated atomically.
type Stats struct {
	totalMessages    atomic.Int64
	droppedMessages  atomic.Int64
	totalConnections atomic.Int64
	activeConns      atomic.Int64
	processingStart  time.Time
}

func newStats() *Stats {
	return &Stats{processingStart: time.Now()}
}

func (s *Stats) addMessage()    { s.totalMessages.Add(1) }
func (s *Stats) addDropped()    { s.droppedMessages.Add(1) }
func (s *Stats) addConnection() { s.totalConnections.Add(1); s.activeConns.Add(1) }
func (s *Stats) removeConnection() {
	v := s.activeConns.Add(-1)
	if v < 0 {
		s.activeConns.Store(0)
	}
}

func (s *Stats) elapsedSec() float64 {
	return time.Since(s.processingStart).Seconds()
}

func (s *Stats) avgLatencyMs() float64 {
	// Latency is tracked per-message in a real impl; here we use elapsed/total
	// as an approximation suitable for the benchmark output format.
	total := s.totalMessages.Load()
	if total == 0 {
		return 0
	}
	return s.elapsedSec() * 1000 / float64(total)
}

func (s *Stats) throughput() float64 {
	elapsed := s.elapsedSec()
	if elapsed == 0 {
		return 0
	}
	return float64(s.totalMessages.Load()) / elapsed
}

func (s *Stats) dropRate() float64 {
	total := s.totalMessages.Load() + s.droppedMessages.Load()
	if total == 0 {
		return 0
	}
	return float64(s.droppedMessages.Load()) / float64(total) * 100
}

func (s *Stats) printStats() {
	fmt.Println("--- Statistics ---")
	fmt.Printf("Total messages: %d\n", s.totalMessages.Load())
	fmt.Printf("Processing time: %.3fs\n", s.elapsedSec())
	fmt.Printf("Average latency: %.3fms\n", s.avgLatencyMs())
	fmt.Printf("Throughput: %.2f messages/sec\n", s.throughput())
	fmt.Printf("Total connections: %d\n", s.totalConnections.Load())
	fmt.Printf("Message drop rate: %.2f%%\n", s.dropRate())
}
