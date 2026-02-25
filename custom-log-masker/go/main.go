package main

import (
	"bufio"
	"flag"
	"fmt"
	"io"
	"os"
	"regexp"
	"runtime"
	"time"
)

// MaskingRule defines a pattern and its replacement
type MaskingRule struct {
	Name        string
	Pattern     *regexp.Regexp
	Replacement string
}

// Stats holds processing statistics
type Stats struct {
	LinesProcessed int
	BytesRead      int64
	BytesWritten   int64
	MatchesFound   int
	StartTime      time.Time
}

func (s *Stats) throughputMBps() float64 {
	elapsed := time.Since(s.StartTime).Seconds()
	if elapsed == 0 {
		return 0
	}
	return float64(s.BytesRead) / 1024 / 1024 / elapsed
}

func (s *Stats) linesPerSec() float64 {
	elapsed := time.Since(s.StartTime).Seconds()
	if elapsed == 0 {
		return 0
	}
	return float64(s.LinesProcessed) / elapsed
}

// createRules initializes all masking rules
func createRules() []MaskingRule {
	return []MaskingRule{
		{
			Name:        "email",
			Pattern:     regexp.MustCompile(`[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}`),
			Replacement: "[EMAIL_MASKED]",
		},
		{
			Name:        "phone",
			Pattern:     regexp.MustCompile(`\b(?:\+?1[-.]?)?\(?[0-9]{3}\)?[-.]?[0-9]{3}[-.]?[0-9]{4}\b`),
			Replacement: "[PHONE_MASKED]",
		},
		{
			Name:        "credit_card",
			Pattern:     regexp.MustCompile(`\b(?:4[0-9]{12}(?:[0-9]{3})?|5[1-5][0-9]{14}|3[47][0-9]{13}|3(?:0[0-5]|[68][0-9])[0-9]{11}|6(?:011|5[0-9]{2})[0-9]{12}|(?:2131|1800|35\d{3})\d{11})\b`),
			Replacement: "[CC_MASKED]",
		},
		{
			Name:        "ssn",
			Pattern:     regexp.MustCompile(`\b[0-9]{3}-[0-9]{2}-[0-9]{4}\b`),
			Replacement: "[SSN_MASKED]",
		},
		{
			Name:        "api_key",
			Pattern:     regexp.MustCompile(`(?i)(api[_-]?key|token|secret)[\s]*[:=][\s]*["']?[a-zA-Z0-9_\-]{16,}["']?`),
			Replacement: "[API_KEY_MASKED]",
		},
		{
			Name:        "password_in_url",
			Pattern:     regexp.MustCompile(`(?i)(password|pwd|pass)[=:][^&\s]+`),
			Replacement: "[PASSWORD_MASKED]",
		},
		{
			Name:        "ip_address",
			Pattern:     regexp.MustCompile(`\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b`),
			Replacement: "[IP_MASKED]",
		},
	}
}

// maskLine applies all masking rules to a line
func maskLine(line string, rules []MaskingRule, stats *Stats) string {
	result := line
	for _, rule := range rules {
		matches := rule.Pattern.FindAllStringIndex(result, -1)
		if len(matches) > 0 {
			stats.MatchesFound += len(matches)
			result = rule.Pattern.ReplaceAllString(result, rule.Replacement)
		}
	}
	return result
}

// processStreams reads from input, masks, and writes to output
func processStreams(input io.Reader, output io.Writer, rules []MaskingRule, stats *Stats) error {
	reader := bufio.NewReaderSize(input, 64*1024) // 64KB buffer
	writer := bufio.NewWriterSize(output, 64*1024)
	defer writer.Flush()

	stats.StartTime = time.Now()

	for {
		line, err := reader.ReadString('\n')
		if len(line) > 0 {
			stats.LinesProcessed++
			stats.BytesRead += int64(len(line))

			masked := maskLine(line, rules, stats)
			n, _ := writer.WriteString(masked)
			stats.BytesWritten += int64(n)
		}

		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
	}

	return nil
}

func main() {
	var (
		inputFile  = flag.String("input", "", "Input log file (default: stdin)")
		outputFile = flag.String("output", "", "Output file (default: stdout)")
		showStats  = flag.Bool("stats", true, "Show processing statistics")
	)
	flag.Parse()

	// Setup input
	var input io.Reader = os.Stdin
	if *inputFile != "" {
		file, err := os.Open(*inputFile)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error opening input: %v\n", err)
			os.Exit(1)
		}
		defer file.Close()
		input = file
	}

	// Setup output
	var output io.Writer = os.Stdout
	if *outputFile != "" {
		file, err := os.Create(*outputFile)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error creating output: %v\n", err)
			os.Exit(1)
		}
		defer file.Close()
		output = file
	}

	rules := createRules()
	stats := &Stats{}

	if err := processStreams(input, output, rules, stats); err != nil {
		fmt.Fprintf(os.Stderr, "Error processing: %v\n", err)
		os.Exit(1)
	}

	if *showStats {
		elapsed := time.Since(stats.StartTime)
		fmt.Fprintf(os.Stderr, "\n--- Statistics ---\n")
		fmt.Fprintf(os.Stderr, "Lines processed: %d\n", stats.LinesProcessed)
		fmt.Fprintf(os.Stderr, "Bytes read: %d\n", stats.BytesRead)
		fmt.Fprintf(os.Stderr, "Matches found: %d\n", stats.MatchesFound)
		fmt.Fprintf(os.Stderr, "Processing time: %.3fs\n", elapsed.Seconds())
		fmt.Fprintf(os.Stderr, "Throughput: %.2f MB/s\n", stats.throughputMBps())
		fmt.Fprintf(os.Stderr, "Lines/sec: %.0f\n", stats.linesPerSec())
	}

	// Prevent GC from being optimized away
	runtime.KeepAlive(rules)
}
