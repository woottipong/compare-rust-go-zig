package main

import (
	"encoding/json"
	"fmt"
	"math/rand"
	"net/http"
	"os"
	"time"
)

type TranscriptionRequest struct {
	AudioData string `json:"audio_data"`
	Format    string `json:"format"`
	Language  string `json:"language"`
}

type TranscriptionResponse struct {
	Transcription    string  `json:"transcription"`
	Confidence       float64 `json:"confidence"`
	ProcessingTimeMs int64   `json:"processing_time_ms"`
}

func main() {
	listenAddr := ":3000"
	if len(os.Args) > 1 {
		listenAddr = os.Args[1]
	}

	rand.Seed(time.Now().UnixNano())

	http.HandleFunc("/transcribe", handleTranscribe)
	http.HandleFunc("/health", handleHealth)

	fmt.Printf("Mock ASR Backend listening on %s\n", listenAddr)
	if err := http.ListenAndServe(listenAddr, nil); err != nil {
		fmt.Fprintf(os.Stderr, "Server error: %v\n", err)
		os.Exit(1)
	}
}

func handleTranscribe(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req TranscriptionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request", http.StatusBadRequest)
		return
	}

	// Simulate processing time (10-50ms)
	processingTime := rand.Int63n(40) + 10
	time.Sleep(time.Duration(processingTime) * time.Millisecond)

	resp := TranscriptionResponse{
		Transcription:    "mock transcription result from ASR service",
		Confidence:       0.95,
		ProcessingTimeMs: processingTime,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}
