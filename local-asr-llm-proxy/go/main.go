package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"runtime"
	"sync"
	"sync/atomic"
	"time"
)

// Stats holds performance metrics
type Stats struct {
	totalProcessed   int64
	totalLatencyNs   int64
	processingTimeNs int64
	startTime        time.Time
}

func (s *Stats) addRequest(latencyNs int64) {
	atomic.AddInt64(&s.totalProcessed, 1)
	atomic.AddInt64(&s.totalLatencyNs, latencyNs)
}

func (s *Stats) getStats() (int64, float64, float64, float64) {
	total := atomic.LoadInt64(&s.totalProcessed)
	latencyNs := atomic.LoadInt64(&s.totalLatencyNs)
	elapsed := time.Since(s.startTime).Seconds()

	var avgLatencyMs, throughput float64
	if total > 0 {
		avgLatencyMs = float64(latencyNs/int64(total)) / float64(time.Millisecond)
	}
	if elapsed > 0 {
		throughput = float64(total) / elapsed
	}

	return total, elapsed, avgLatencyMs, throughput
}

// Job represents a transcription job
type Job struct {
	ID         string
	AudioData  string
	Format     string
	Language   string
	ResponseCh chan *TranscriptionResponse
}

// TranscriptionRequest is the request body
type TranscriptionRequest struct {
	AudioData string `json:"audio_data"`
	Format    string `json:"format"`
	Language  string `json:"language"`
}

// TranscriptionResponse is the response body
type TranscriptionResponse struct {
	JobID            string `json:"job_id"`
	Status           string `json:"status"`
	Transcription    string `json:"transcription"`
	ProcessingTimeMs int64  `json:"processing_time_ms"`
}

// BackendResponse is the response from mock backend
type BackendResponse struct {
	Transcription    string  `json:"transcription"`
	Confidence       float64 `json:"confidence"`
	ProcessingTimeMs int64   `json:"processing_time_ms"`
}

// Config holds application configuration
type Config struct {
	ListenAddr  string
	BackendURL  string
	WorkerCount int
	QueueSize   int
}

func main() {
	cfg := parseArgs()
	printConfig(cfg)

	stats := &Stats{startTime: time.Now()}
	jobQueue := make(chan *Job, cfg.QueueSize)

	// Start workers
	var wg sync.WaitGroup
	for i := 0; i < cfg.WorkerCount; i++ {
		wg.Add(1)
		go worker(i, jobQueue, cfg.BackendURL, stats, &wg)
	}

	// Setup HTTP routes
	mux := http.NewServeMux()
	mux.HandleFunc("/transcribe", handleTranscribe(jobQueue))
	mux.HandleFunc("/health", handleHealth)
	mux.HandleFunc("/stats", handleStats(stats))

	server := &http.Server{
		Addr:         cfg.ListenAddr,
		Handler:      mux,
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 5 * time.Second,
	}

	fmt.Printf("Server listening on %s\n", cfg.ListenAddr)
	if err := server.ListenAndServe(); err != nil {
		fmt.Fprintf(os.Stderr, "Server error: %v\n", err)
		os.Exit(1)
	}
}

func parseArgs() *Config {
	listenAddr := ":8080"
	backendURL := "http://localhost:3000"
	workerCount := runtime.NumCPU()
	queueSize := 1000

	args := os.Args[1:]
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "-listen", "-l":
			if i+1 < len(args) {
				listenAddr = args[i+1]
				i++
			}
		case "-backend", "-b":
			if i+1 < len(args) {
				backendURL = args[i+1]
				i++
			}
		case "-workers", "-w":
			if i+1 < len(args) {
				fmt.Sscanf(args[i+1], "%d", &workerCount)
				i++
			}
		case "-queue", "-q":
			if i+1 < len(args) {
				fmt.Sscanf(args[i+1], "%d", &queueSize)
				i++
			}
		}
	}

	return &Config{
		ListenAddr:  listenAddr,
		BackendURL:  backendURL,
		WorkerCount: workerCount,
		QueueSize:   queueSize,
	}
}

func printConfig(cfg *Config) {
	fmt.Println("── Configuration ─────────────────────")
	fmt.Printf("  Listen Addr : %s\n", cfg.ListenAddr)
	fmt.Printf("  Backend URL : %s\n", cfg.BackendURL)
	fmt.Printf("  Workers     : %d\n", cfg.WorkerCount)
	fmt.Printf("  Queue Size  : %d\n", cfg.QueueSize)
	fmt.Println()
}

func worker(id int, jobQueue <-chan *Job, backendURL string, stats *Stats, wg *sync.WaitGroup) {
	defer wg.Done()

	client := &http.Client{
		Timeout: 3 * time.Second,
		Transport: &http.Transport{
			MaxIdleConns:        10,
			MaxIdleConnsPerHost: 10,
			IdleConnTimeout:     30 * time.Second,
		},
	}

	for job := range jobQueue {
		start := time.Now()

		// Forward to backend
		resp, err := forwardToBackend(client, backendURL, job)
		if err != nil {
			resp = &TranscriptionResponse{
				JobID:            job.ID,
				Status:           "error",
				Transcription:    fmt.Sprintf("Error: %v", err),
				ProcessingTimeMs: 0,
			}
		}

		// Record stats
		latency := time.Since(start)
		stats.addRequest(int64(latency))

		// Send response
		job.ResponseCh <- resp
	}
}

func forwardToBackend(client *http.Client, backendURL string, job *Job) (*TranscriptionResponse, error) {
	reqBody := map[string]string{
		"audio_data": job.AudioData,
		"format":     job.Format,
		"language":   job.Language,
	}
	jsonBody, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("marshal request: %w", err)
	}

	req, err := http.NewRequest("POST", backendURL+"/transcribe", bytes.NewReader(jsonBody))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("do request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}

	var backendResp BackendResponse
	if err := json.Unmarshal(body, &backendResp); err != nil {
		return nil, fmt.Errorf("unmarshal response: %w", err)
	}

	return &TranscriptionResponse{
		JobID:            job.ID,
		Status:           "completed",
		Transcription:    backendResp.Transcription,
		ProcessingTimeMs: backendResp.ProcessingTimeMs,
	}, nil
}

func handleTranscribe(jobQueue chan<- *Job) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}

		var req TranscriptionRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, fmt.Sprintf("Invalid request: %v", err), http.StatusBadRequest)
			return
		}

		// Create job
		job := &Job{
			ID:         generateID(),
			AudioData:  req.AudioData,
			Format:     req.Format,
			Language:   req.Language,
			ResponseCh: make(chan *TranscriptionResponse, 1),
		}

		// Enqueue job
		select {
		case jobQueue <- job:
		default:
			http.Error(w, "Queue full", http.StatusServiceUnavailable)
			return
		}

		// Wait for response
		select {
		case resp := <-job.ResponseCh:
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(resp)
		case <-time.After(5 * time.Second):
			http.Error(w, "Request timeout", http.StatusGatewayTimeout)
		}
	}
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

func handleStats(stats *Stats) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		total, elapsed, avgLatencyMs, throughput := stats.getStats()

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"total_processed":    total,
			"processing_time_s":  elapsed,
			"average_latency_ms": avgLatencyMs,
			"throughput":         throughput,
		})
	}
}

func generateID() string {
	return fmt.Sprintf("%d", time.Now().UnixNano())
}
