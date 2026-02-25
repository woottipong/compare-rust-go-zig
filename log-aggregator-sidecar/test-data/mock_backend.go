package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"sync/atomic"
	"time"
)

type Stats struct {
	totalReceived int64
	startTime     time.Time
}

type LogEntry struct {
	Timestamp string `json:"timestamp"`
	Level     string `json:"level"`
	App       string `json:"app"`
	PID       int    `json:"pid"`
	Message   string `json:"message"`
	Source    string `json:"source"`
}

var stats Stats

func main() {
	stats.startTime = time.Now()
	
	listenAddr := ":9200"
	if len(os.Args) > 1 {
		listenAddr = os.Args[1]
	}

	http.HandleFunc("/health", handleHealth)
	http.HandleFunc("/stats", handleStats)
	http.HandleFunc("/", handleLogs) // Accept any path for logs

	fmt.Printf("Mock Log Backend listening on %s\n", listenAddr)
	log.Fatal(http.ListenAndServe(listenAddr, nil))
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

func handleStats(w http.ResponseWriter, r *http.Request) {
	elapsed := time.Since(stats.startTime).Seconds()
	throughput := float64(atomic.LoadInt64(&stats.totalReceived)) / elapsed
	
	response := map[string]interface{}{
		"total_received": atomic.LoadInt64(&stats.totalReceived),
		"processing_time": elapsed,
		"throughput": throughput,
	}
	
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func handleLogs(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var entry LogEntry
	if err := json.NewDecoder(r.Body).Decode(&entry); err != nil {
		// Try to parse as array of entries
		var entries []LogEntry
		if err := json.NewDecoder(r.Body).Decode(&entries); err != nil {
			http.Error(w, "Invalid JSON", http.StatusBadRequest)
			return
		}
		atomic.AddInt64(&stats.totalReceived, int64(len(entries)))
	} else {
		atomic.AddInt64(&stats.totalReceived, 1)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "received"})
}
