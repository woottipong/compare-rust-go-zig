package main

import (
	"fmt"
	"io"
	"log"
	"os"
	"sync"
	"time"
)

const (
	sampleRate        = 16000
	channels          = 1
	bitsPerSample     = 16
	bytesPerSample    = bitsPerSample / 8
	chunkDurationMs   = 25
	overlapDurationMs = 10
	chunkDuration     = chunkDurationMs * time.Millisecond
	overlapDuration   = overlapDurationMs * time.Millisecond
	inputIntervalMs   = 10
	inputInterval     = inputIntervalMs * time.Millisecond
)

// chunkSamples returns the number of PCM samples for a given duration in ms.
func chunkSamples(durationMs int) int {
	return sampleRate * durationMs / 1000
}

type AudioChunk struct {
	Data      []byte
	Timestamp time.Time
	Index     int
}

type Stats struct {
	TotalChunks    int
	TotalLatency   time.Duration
	ProcessingTime time.Duration
}

func (s Stats) AvgLatencyMs() float64 {
	if s.TotalChunks == 0 {
		return 0
	}
	avg := s.TotalLatency / time.Duration(s.TotalChunks)
	return float64(avg.Nanoseconds()) / 1e6
}

func (s Stats) Throughput() float64 {
	if s.ProcessingTime == 0 {
		return 0
	}
	return float64(s.TotalChunks) / s.ProcessingTime.Seconds()
}

type AudioChunker struct {
	chunkSize   int
	overlapSize int
	buffer      []byte
	bufferPos   int
	chunkIndex  int
	outputChan  chan AudioChunk
	wg          sync.WaitGroup
}

func newAudioChunker() *AudioChunker {
	cs := chunkSamples(chunkDurationMs) * channels * bytesPerSample
	os_ := chunkSamples(overlapDurationMs) * channels * bytesPerSample
	return &AudioChunker{
		chunkSize:   cs,
		overlapSize: os_,
		buffer:      make([]byte, cs*2),
		outputChan:  make(chan AudioChunk, 100),
	}
}

func (ac *AudioChunker) processAudio(data []byte) {
	copy(ac.buffer[ac.bufferPos:], data)
	ac.bufferPos += len(data)

	for ac.bufferPos >= ac.chunkSize {
		chunk := make([]byte, ac.chunkSize)
		copy(chunk, ac.buffer[:ac.chunkSize])
		ac.outputChan <- AudioChunk{Data: chunk, Timestamp: time.Now(), Index: ac.chunkIndex}
		ac.chunkIndex++

		remaining := ac.bufferPos - ac.chunkSize
		copy(ac.buffer, ac.buffer[ac.chunkSize-ac.overlapSize:ac.bufferPos])
		ac.bufferPos = remaining + ac.overlapSize
	}
}

func (ac *AudioChunker) finalize() {
	close(ac.outputChan)
}

func (ac *AudioChunker) startProcessor() <-chan Stats {
	statsCh := make(chan Stats, 1)
	ac.wg.Add(1)
	go func() {
		defer ac.wg.Done()
		var s Stats
		for chunk := range ac.outputChan {
			latency := time.Since(chunk.Timestamp)
			s.TotalLatency += latency
			s.TotalChunks++
			if s.TotalChunks <= 5 || s.TotalChunks%20 == 0 {
				fmt.Printf("Chunk %d: %d bytes, latency: %.3fms\n",
					chunk.Index, len(chunk.Data), float64(latency.Nanoseconds())/1e6)
			}
		}
		statsCh <- s
	}()
	return statsCh
}

func (ac *AudioChunker) wait() {
	ac.wg.Wait()
}

func readWAVFile(filename string) ([]byte, error) {
	file, err := os.Open(filename)
	if err != nil {
		return nil, fmt.Errorf("open %s: %w", filename, err)
	}
	defer file.Close()

	if _, err = file.Seek(44, io.SeekStart); err != nil {
		return nil, fmt.Errorf("seek past WAV header: %w", err)
	}

	data, err := io.ReadAll(file)
	if err != nil {
		return nil, fmt.Errorf("read audio data: %w", err)
	}
	return data, nil
}

func printConfig(audioDataLen int) {
	cs := chunkSamples(chunkDurationMs) * channels * bytesPerSample
	os_ := chunkSamples(overlapDurationMs) * channels * bytesPerSample
	fmt.Printf("Audio data size: %d bytes\n", audioDataLen)
	fmt.Printf("Chunk size: %d bytes (%v)\n", cs, chunkDuration)
	fmt.Printf("Overlap size: %d bytes (%v)\n", os_, overlapDuration)
}

func simulateRealTimeInput(audioData []byte, chunker *AudioChunker) {
	bytesPerInterval := sampleRate * channels * bytesPerSample * inputIntervalMs / 1000

	for i := 0; i < len(audioData); i += bytesPerInterval {
		end := i + bytesPerInterval
		if end > len(audioData) {
			end = len(audioData)
		}
		chunker.processAudio(audioData[i:end])
		time.Sleep(inputInterval)
	}
}

func printStats(s Stats) {
	fmt.Printf("\n--- Statistics ---\n")
	fmt.Printf("Total chunks: %d\n", s.TotalChunks)
	fmt.Printf("Processing time: %.3fs\n", s.ProcessingTime.Seconds())
	fmt.Printf("Average latency: %.3fms\n", s.AvgLatencyMs())
	fmt.Printf("Throughput: %.2f chunks/sec\n", s.Throughput())
}

func main() {
	if len(os.Args) < 2 {
		log.Fatal("Usage: realtime-audio-chunker <input.wav>")
	}
	inputFile := os.Args[1]

	audioData, err := readWAVFile(inputFile)
	if err != nil {
		log.Fatalf("Failed to read audio file: %v", err)
	}

	fmt.Printf("Processing audio file: %s\n", inputFile)
	printConfig(len(audioData))

	chunker := newAudioChunker()
	statsCh := chunker.startProcessor()

	startTime := time.Now()
	simulateRealTimeInput(audioData, chunker)
	chunker.finalize()
	chunker.wait()
	processingTime := time.Since(startTime)

	stats := <-statsCh
	stats.ProcessingTime = processingTime

	if stats.TotalChunks > 0 {
		printStats(stats)
	}
}
