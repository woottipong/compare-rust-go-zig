package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/fsnotify/fsnotify"
)

// ============================================================================
// Data Structures
// ============================================================================

type LogEntry struct {
	Timestamp string `json:"timestamp"`
	Level     string `json:"level"`
	App       string `json:"app"`
	PID       int    `json:"pid"`
	Message   string `json:"message"`
	Source    string `json:"source"`
}

type Stats struct {
	totalProcessed int64
	totalBytes     int64
	startTime      time.Time
}

func (s *Stats) addEntry(bytes int) {
	atomic.AddInt64(&s.totalProcessed, 1)
	atomic.AddInt64(&s.totalBytes, int64(bytes))
}

func (s *Stats) getStats() map[string]interface{} {
	total := atomic.LoadInt64(&s.totalProcessed)
	bytes := atomic.LoadInt64(&s.totalBytes)
	elapsed := time.Since(s.startTime).Seconds()

	throughput := float64(total) / elapsed
	if elapsed == 0 {
		throughput = 0
	}

	return map[string]interface{}{
		"total_processed": total,
		"total_bytes":     bytes,
		"processing_time": elapsed,
		"throughput":      throughput,
	}
}

func (s *Stats) printStats() {
	stats := s.getStats()
	fmt.Printf("--- Statistics ---\n")
	fmt.Printf("Total processed: %v\n", stats["total_processed"])
	fmt.Printf("Processing time: %.3fs\n", stats["processing_time"])
	fmt.Printf("Throughput: %.2f lines/sec\n", stats["throughput"])
}

func (s *Stats) getStatsHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(s.getStats())
}

func (s *Stats) healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

// ============================================================================
// Configuration
// ============================================================================

type Config struct {
	inputFile  string
	outputURL  string
	bufferSize int
	workers    int
	oneShot    bool
}

func parseConfig() *Config {
	config := &Config{}
	flag.StringVar(&config.inputFile, "input", "", "Input log file to watch")
	flag.StringVar(&config.outputURL, "output", "", "Output URL to send logs")
	flag.IntVar(&config.bufferSize, "buffer", 1000, "Buffer size for batch processing")
	flag.IntVar(&config.workers, "workers", 4, "Number of worker goroutines")
	flag.BoolVar(&config.oneShot, "one-shot", false, "Process file once, print stats, then exit")
	flag.Parse()

	if config.inputFile == "" || config.outputURL == "" {
		log.Fatal("Both --input and --output are required")
	}

	return config
}

func printConfig(config *Config) {
	fmt.Printf("── Configuration ─────────────────────\n")
	fmt.Printf("  Input File : %s\n", config.inputFile)
	fmt.Printf("  Output URL : %s\n", config.outputURL)
	fmt.Printf("  Buffer     : %d\n", config.bufferSize)
	fmt.Printf("  Workers    : %d\n", config.workers)
	fmt.Printf("\n")
}

// ============================================================================
// Log Parser
// ============================================================================

// Parse log format: "2023-03-15 10:30:45 INFO auth[5]: User 1234 login from 192.168.1.100"
var logPattern = regexp.MustCompile(`^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) (\w+) (\w+)\[(\d+)\]: (.*)$`)

func parseLogLine(line string, source string) (*LogEntry, error) {
	matches := logPattern.FindStringSubmatch(line)
	if matches == nil {
		// Return raw line as message if pattern doesn't match
		return &LogEntry{
			Timestamp: time.Now().Format("2006-01-02 15:04:05"),
			Level:     "UNKNOWN",
			App:       "raw",
			PID:       0,
			Message:   strings.TrimSpace(line),
			Source:    source,
		}, nil
	}

	// Parse PID from matches[4]
	pid := 0
	if len(matches) >= 5 {
		var err error
		pid, err = strconv.Atoi(matches[4])
		if err != nil {
			pid = 0
		}
	}

	return &LogEntry{
		Timestamp: matches[1],
		Level:     matches[2],
		App:       matches[3],
		PID:       pid,
		Message:   matches[5],
		Source:    source,
	}, nil
}

// ============================================================================
// Forwarder
// ============================================================================

type Forwarder struct {
	client    *http.Client
	outputURL string
	buffer    chan []byte
	stats     *Stats
	wg        sync.WaitGroup
}

func NewForwarder(outputURL string, bufferSize int, stats *Stats) *Forwarder {
	transport := &http.Transport{
		MaxIdleConns:        100,
		MaxIdleConnsPerHost: 100,
		IdleConnTimeout:     90 * time.Second,
		DisableKeepAlives:   false,
	}
	return &Forwarder{
		client:    &http.Client{Timeout: 5 * time.Second, Transport: transport},
		outputURL: outputURL,
		buffer:    make(chan []byte, bufferSize),
		stats:     stats,
	}
}

func (f *Forwarder) start(workers int) {
	for i := 0; i < workers; i++ {
		f.wg.Add(1)
		go f.worker()
	}
}

func (f *Forwarder) worker() {
	defer f.wg.Done()

	for batch := range f.buffer {
		if err := f.sendBatch(batch); err != nil {
			log.Printf("Failed to send batch: %v", err)
		}
	}
}

func (f *Forwarder) sendBatch(batch []byte) error {
	req, err := http.NewRequest("POST", f.outputURL, strings.NewReader(string(batch)))
	if err != nil {
		return err
	}

	req.Header.Set("Content-Type", "application/json")

	resp, err := f.client.Do(req)
	if err != nil {
		return err
	}
	io.Copy(io.Discard, resp.Body)
	resp.Body.Close()

	if resp.StatusCode >= 400 {
		return fmt.Errorf("HTTP %d", resp.StatusCode)
	}

	return nil
}

func (f *Forwarder) send(entry *LogEntry) error {
	data, err := json.Marshal(entry)
	if err != nil {
		return err
	}

	f.stats.addEntry(len(data))

	f.buffer <- data
	return nil
}

func (f *Forwarder) stop() {
	close(f.buffer)
	f.wg.Wait()
}

// ============================================================================
// File Watcher
// ============================================================================

func watchFile(config *Config, forwarder *Forwarder, stats *Stats) error {
	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		return err
	}
	defer watcher.Close()

	// Watch the directory containing the file
	dir := filepath.Dir(config.inputFile)
	if err := watcher.Add(dir); err != nil {
		return err
	}

	// Process existing file first
	if err := processFile(config.inputFile, forwarder, stats); err != nil {
		log.Printf("Error processing initial file: %v", err)
	}

	fmt.Printf("Watching %s for changes...\n", config.inputFile)

	// Print initial stats
	fmt.Printf("Processed %d lines so far\n", atomic.LoadInt64(&stats.totalProcessed))

	for {
		select {
		case event, ok := <-watcher.Events:
			if !ok {
				return fmt.Errorf("watcher closed")
			}

			// Only process the target file
			if event.Name != config.inputFile {
				continue
			}

			if event.Op&fsnotify.Write == fsnotify.Write {
				if err := processFile(config.inputFile, forwarder, stats); err != nil {
					log.Printf("Error processing file: %v", err)
				}
			}

		case err, ok := <-watcher.Errors:
			if !ok {
				return fmt.Errorf("error channel closed")
			}
			return fmt.Errorf("watcher error: %v", err)
		}
	}
}

func processFile(filename string, forwarder *Forwarder, stats *Stats) error {
	file, err := os.Open(filename)
	if err != nil {
		return err
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	lineCount := 0

	for scanner.Scan() {
		line := scanner.Text()
		if line == "" {
			continue
		}

		entry, err := parseLogLine(line, filename)
		if err != nil {
			log.Printf("Parse error: %v", err)
			continue
		}

		if err := forwarder.send(entry); err != nil {
			log.Printf("Forward error: %v", err)
		}

		lineCount++
	}

	if lineCount > 0 {
		fmt.Printf("Processed %d lines from %s\n", lineCount, filename)
	}

	return scanner.Err()
}

// ============================================================================
// Main
// ============================================================================

func main() {
	config := parseConfig()
	printConfig(config)

	stats := &Stats{startTime: time.Now()}
	forwarder := NewForwarder(config.outputURL, config.bufferSize, stats)

	if config.oneShot {
		forwarder.start(config.workers)
		if err := processFile(config.inputFile, forwarder, stats); err != nil {
			log.Fatalf("Error processing file: %v", err)
		}
		forwarder.stop()
		stats.printStats()
		return
	}

	// Start HTTP server for stats
	http.HandleFunc("/stats", stats.getStatsHandler)
	http.HandleFunc("/health", stats.healthHandler)
	go func() {
		log.Fatal(http.ListenAndServe(":8080", nil))
	}()

	// Start forwarder workers
	forwarder.start(config.workers)
	defer forwarder.stop()

	// Start file watcher
	if err := watchFile(config, forwarder, stats); err != nil {
		log.Fatal(err)
	}
}
