package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

type KVStore struct {
	mu   sync.RWMutex
	data map[string]string
}

func newKVStore() *KVStore {
	return &KVStore{
		data: make(map[string]string),
	}
}

func (kv *KVStore) set(key, value string) {
	kv.mu.Lock()
	defer kv.mu.Unlock()
	kv.data[key] = value
}

func (kv *KVStore) get(key string) (string, bool) {
	kv.mu.RLock()
	defer kv.mu.RUnlock()
	value, exists := kv.data[key]
	return value, exists
}

func (kv *KVStore) delete(key string) bool {
	kv.mu.Lock()
	defer kv.mu.Unlock()
	if _, exists := kv.data[key]; exists {
		delete(kv.data, key)
		return true
	}
	return false
}

type Stats struct {
	totalOps     int
	processingNs int64
}

func (s Stats) avgLatencyMs() float64 {
	if s.totalOps == 0 {
		return 0
	}
	return float64(s.processingNs) / 1e6 / float64(s.totalOps)
}

func (s Stats) throughput() float64 {
	if s.processingNs == 0 {
		return 0
	}
	return float64(s.totalOps) * 1e9 / float64(s.processingNs)
}

func parseArgs() (int, error) {
	if len(os.Args) < 2 {
		return 10000, nil // default
	}
	numOps, err := strconv.Atoi(os.Args[1])
	if err != nil || numOps <= 0 {
		return 0, fmt.Errorf("invalid number of operations: %s", os.Args[1])
	}
	return numOps, nil
}

func printConfig(numOps int) {
	fmt.Printf("Configuration:\n")
	fmt.Printf("  Operations: %d\n", numOps)
	fmt.Printf("  Store type: In-memory KV Store\n\n")
}

func printStats(stats Stats) {
	fmt.Printf("--- Statistics ---\n")
	fmt.Printf("Total processed: %d\n", stats.totalOps)
	fmt.Printf("Processing time: %.3fs\n", float64(stats.processingNs)/1e9)
	fmt.Printf("Average latency: %.6fms\n", stats.avgLatencyMs())
	fmt.Printf("Throughput: %.0f ops/sec\n", stats.throughput())
}

func generateTestData(numOps int) ([]string, []string) {
	keys := make([]string, numOps)
	values := make([]string, numOps)

	keyPatterns := []string{
		"user:%d:name", "session:%s:token", "product:%d:price",
		"cache:page:%d", "temp:calc:%d", "config:app:%s",
		"auth:user:%d", "cart:item:%d", "order:%d:status",
		"inventory:%d:count", "log:%d:entry", "metric:%s:value",
		"short", "id:%d", "very_long_key_name_with_descriptors:%d",
		"api:response:%d", "db:query:%d", "file:temp:%d",
	}

	valuePatterns := []string{
		"John Doe", "active", "true", "false", "123.45",
		`{"name":"product","price":99.99,"stock":50}`,
		`{"user_id":12345,"session":"abc123xyz","expires":3600}`,
		"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ",
		"<html><body><h1>Page Content</h1></body></html>",
		"Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.",
		"result:42.5:calculation_complete", "pending", "completed", "failed",
		"1", "2", "3", "4", "5", "10", "100", "1000",
		"small_value", "medium_sized_value_with_more_content", "very_large_value_that_contains_much_more_text_and_data_to_simulate_real_world_storage_requirements",
		"2024-02-26T18:18:00Z", "admin", "user", "guest",
	}

	for i := 0; i < numOps; i++ {
		keyPattern := keyPatterns[i%len(keyPatterns)]
		valuePattern := valuePatterns[i%len(valuePatterns)]

		if strings.Contains(keyPattern, "%d") {
			keys[i] = fmt.Sprintf(keyPattern, i)
		} else if strings.Contains(keyPattern, "%s") {
			keys[i] = fmt.Sprintf(keyPattern, fmt.Sprintf("id%d", i))
		} else {
			keys[i] = fmt.Sprintf("%s_%d", keyPattern, i)
		}

		if strings.Contains(valuePattern, "%d") {
			values[i] = fmt.Sprintf(valuePattern, i)
		} else if strings.Contains(valuePattern, "%s") {
			values[i] = fmt.Sprintf(valuePattern, fmt.Sprintf("val%d", i))
		} else {
			values[i] = valuePattern
		}
	}

	return keys, values
}

func runBenchmark(numOps int) Stats {
	kv := newKVStore()

	// Generate realistic test data
	keys, values := generateTestData(numOps)

	start := time.Now()

	// SET operations
	for i := 0; i < numOps; i++ {
		kv.set(keys[i], values[i])
	}

	// GET operations
	for i := 0; i < numOps; i++ {
		kv.get(keys[i])
	}

	// DELETE operations (half of them)
	for i := 0; i < numOps/2; i++ {
		kv.delete(keys[i])
	}

	elapsed := time.Since(start)

	return Stats{
		totalOps:     numOps*2 + numOps/2, // SET + GET + DELETE
		processingNs: elapsed.Nanoseconds(),
	}
}

func main() {
	numOps, err := parseArgs()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	printConfig(numOps)
	stats := runBenchmark(numOps)
	printStats(stats)
}
