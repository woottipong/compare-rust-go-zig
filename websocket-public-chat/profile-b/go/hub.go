package main

import "sync"

// Hub maintains the set of active clients and broadcasts messages to them.
type Hub struct {
	clients    map[*Client]bool
	broadcast  chan []byte
	register   chan *Client
	unregister chan *Client
	mu         sync.RWMutex
	stats      *Stats
}

func newHub(stats *Stats) *Hub {
	return &Hub{
		clients:    make(map[*Client]bool),
		broadcast:  make(chan []byte, 256),
		register:   make(chan *Client, 64),
		unregister: make(chan *Client, 64),
		stats:      stats,
	}
}

// run processes hub events. Must be called in its own goroutine.
func (h *Hub) run() {
	for {
		select {
		case client := <-h.register:
			h.mu.Lock()
			h.clients[client] = true
			h.mu.Unlock()
			h.stats.addConnection()

		case client := <-h.unregister:
			h.mu.Lock()
			if h.clients[client] {
				delete(h.clients, client)
				close(client.send)
			}
			h.mu.Unlock()
			h.stats.removeConnection()

		case message := <-h.broadcast:
			h.mu.RLock()
			for client := range h.clients {
				select {
				case client.send <- message:
				default:
					// send buffer full — treat as disconnected
				}
			}
			h.mu.RUnlock()
		}
	}
}

// broadcastExcept sends message to all clients except the sender.
func (h *Hub) broadcastExcept(sender *Client, message []byte) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	for client := range h.clients {
		if client == sender {
			continue
		}
		select {
		case client.send <- message:
		default:
			// send buffer full — skip
		}
	}
}

// clientCount returns the current number of registered clients.
func (h *Hub) clientCount() int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.clients)
}
