package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"strings"
	"time"
)

// Config holds the application configuration
type Config struct {
	inputFile string
	batchSize int
	dimSize   int
}

// Stats holds processing statistics
type Stats struct {
	totalDocs    int
	totalChunks  int
	processingNs int64
}

func (s Stats) avgLatencyMs() float64 {
	if s.totalChunks == 0 {
		return 0
	}
	return float64(s.processingNs) / float64(s.totalChunks) / 1e6
}

func (s Stats) throughput() float64 {
	if s.processingNs == 0 {
		return 0
	}
	return float64(s.totalChunks) / (float64(s.processingNs) / 1e9)
}

func printConfig(cfg Config) {
	fmt.Println("--- Configuration ---")
	fmt.Printf("Input file: %s\n", cfg.inputFile)
	fmt.Printf("Batch size: %d\n", cfg.batchSize)
	fmt.Printf("Embedding dimension: %d\n", cfg.dimSize)
}

func printStats(s Stats) {
	fmt.Println("--- Statistics ---")
	fmt.Printf("Total documents: %d\n", s.totalDocs)
	fmt.Printf("Total chunks: %d\n", s.totalChunks)
	fmt.Printf("Processing time: %.3fs\n", float64(s.processingNs)/1e9)
	fmt.Printf("Average latency: %.3fms\n", s.avgLatencyMs())
	fmt.Printf("Throughput: %.2f chunks/sec\n", s.throughput())
}

// Document represents input document
type Document struct {
	ID      string `json:"id"`
	Content string `json:"content"`
	Type    string `json:"type,omitempty"`
}

// Chunk represents a text chunk with embedding
type Chunk struct {
	Text      string
	StartIdx  int
	EndIdx    int
	Embedding []float32
}

// simpleEmbedding generates a simple fixed-dimension embedding
// In production, use ONNX Runtime with all-MiniLM-L6-v2 model
func simpleEmbedding(text string, dim int) []float32 {
	// Generate dim-dimensional embedding
	// Use simple hash-based approach for benchmarking
	embedding := make([]float32, dim)
	textHash := hashString(text)

	for i := 0; i < dim; i++ {
		// Simple pseudo-random based on hash
		embedding[i] = float32((textHash>>uint(i%32))&0xFF) / 255.0
	}

	return embedding
}

// hashString generates a simple hash for text
func hashString(s string) uint64 {
	var h uint64 = 14695981039346656037 // FNV offset basis
	for i := 0; i < len(s); i++ {
		h ^= uint64(s[i])
		h *= 1099511628211 // FNV prime
	}
	return h
}

// chunkText splits text into overlapping chunks
func chunkText(text string, chunkSize, overlap int) []Chunk {
	chunks := []Chunk{}

	// Simple word-based chunking
	words := strings.Fields(text)
	if len(words) == 0 {
		return chunks
	}

	for i := 0; i < len(words); i += chunkSize - overlap {
		end := i + chunkSize
		if end > len(words) {
			end = len(words)
		}

		chunkText := strings.Join(words[i:end], " ")

		chunks = append(chunks, Chunk{
			Text:      chunkText,
			StartIdx:  i,
			EndIdx:    end,
			Embedding: simpleEmbedding(chunkText, 384),
		})

		if end >= len(words) {
			break
		}
	}

	return chunks
}

// parseInputFile reads and parses the input JSON file
func parseInputFile(filename string) ([]Document, error) {
	data, err := os.ReadFile(filename)
	if err != nil {
		return nil, fmt.Errorf("failed to read file: %w", err)
	}

	// Try parsing as new format: {"metadata": {...}, "documents": [...]}
	var newFormat struct {
		Documents []Document `json:"documents"`
	}
	if err := json.Unmarshal(data, &newFormat); err == nil && len(newFormat.Documents) > 0 {
		return newFormat.Documents, nil
	}

	// Try parsing as JSON array (old format)
	var docs []Document
	if err := json.Unmarshal(data, &docs); err == nil {
		return docs, nil
	}

	// Try parsing as single document
	var doc Document
	if err := json.Unmarshal(data, &doc); err == nil {
		return []Document{doc}, nil
	}

	// Try parsing as plain text
	lines := strings.Split(string(data), "\n")
	docs = make([]Document, 0, len(lines))
	for i, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		docs = append(docs, Document{
			ID:      fmt.Sprintf("doc-%03d", i+1),
			Content: line,
			Type:    "txt",
		})
	}
	return docs, nil
}

func main() {
	// Parse flags
	cfg := Config{}
	flag.StringVar(&cfg.inputFile, "input", "test.json", "Input JSON file with documents")
	flag.IntVar(&cfg.batchSize, "batch", 32, "Batch size for embedding")
	flag.IntVar(&cfg.dimSize, "dim", 384, "Embedding dimension")
	flag.Parse()

	// Print config
	printConfig(cfg)

	// Start timer
	startTime := time.Now()

	// Parse input file
	docs, err := parseInputFile(cfg.inputFile)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error parsing input: %v\n", err)
		os.Exit(1)
	}

	// Process documents
	allChunks := []Chunk{}
	for _, doc := range docs {
		chunks := chunkText(doc.Content, 512, 50)
		for i := range chunks {
			chunks[i].Text = doc.ID + ": " + chunks[i].Text
		}
		allChunks = append(allChunks, chunks...)
	}

	processingTime := time.Since(startTime)

	// Calculate stats
	stats := Stats{
		totalDocs:    len(docs),
		totalChunks:  len(allChunks),
		processingNs: processingTime.Nanoseconds(),
	}

	// Print stats
	printStats(stats)
}
