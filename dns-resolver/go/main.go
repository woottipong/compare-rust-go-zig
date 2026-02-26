package main

import (
	"encoding/binary"
	"errors"
	"fmt"
	"net"
	"os"
	"strconv"
	"time"
)

type stats struct {
	totalProcessed uint64
	processingNs   int64
}

func (s stats) avgLatencyMs() float64 {
	if s.totalProcessed == 0 {
		return 0
	}
	return float64(s.processingNs) / 1e6 / float64(s.totalProcessed)
}

func (s stats) throughput() float64 {
	if s.processingNs == 0 {
		return 0
	}
	return float64(s.totalProcessed) * 1e9 / float64(s.processingNs)
}

func parseArgs() (string, int, int, error) {
	host := "host.docker.internal"
	port := 53535
	repeats := 2000
	if len(os.Args) > 1 {
		host = os.Args[1]
	}
	if len(os.Args) > 2 {
		v, err := strconv.Atoi(os.Args[2])
		if err != nil || v < 1 {
			return "", 0, 0, errors.New("port must be positive integer")
		}
		port = v
	}
	if len(os.Args) > 3 {
		v, err := strconv.Atoi(os.Args[3])
		if err != nil || v < 1 {
			return "", 0, 0, errors.New("repeats must be positive integer")
		}
		repeats = v
	}
	return host, port, repeats, nil
}

func buildQuery(id uint16, name string) []byte {
	q := make([]byte, 12)
	binary.BigEndian.PutUint16(q[0:2], id)
	binary.BigEndian.PutUint16(q[2:4], 0x0100)
	binary.BigEndian.PutUint16(q[4:6], 1)
	for _, label := range splitLabels(name) {
		q = append(q, byte(len(label)))
		q = append(q, []byte(label)...)
	}
	q = append(q, 0)
	q = append(q, 0, 1, 0, 1)
	return q
}

func splitLabels(name string) []string {
	var out []string
	start := 0
	for i := 0; i <= len(name); i++ {
		if i == len(name) || name[i] == '.' {
			if i > start {
				out = append(out, name[start:i])
			}
			start = i + 1
		}
	}
	return out
}

func readName(msg []byte, off int) (int, error) {
	for {
		if off >= len(msg) {
			return 0, errors.New("invalid name offset")
		}
		l := int(msg[off])
		off++
		if l == 0 {
			return off, nil
		}
		if l&0xC0 == 0xC0 {
			if off >= len(msg) {
				return 0, errors.New("invalid compressed name")
			}
			return off + 1, nil
		}
		off += l
	}
}

func parseARecordCount(msg []byte) (int, error) {
	if len(msg) < 12 {
		return 0, errors.New("short dns message")
	}
	qd := int(binary.BigEndian.Uint16(msg[4:6]))
	an := int(binary.BigEndian.Uint16(msg[6:8]))
	off := 12
	for i := 0; i < qd; i++ {
		next, err := readName(msg, off)
		if err != nil {
			return 0, err
		}
		off = next + 4
	}
	count := 0
	for i := 0; i < an; i++ {
		next, err := readName(msg, off)
		if err != nil {
			return 0, err
		}
		off = next
		if off+10 > len(msg) {
			return 0, errors.New("invalid rr")
		}
		typeCode := binary.BigEndian.Uint16(msg[off : off+2])
		rdlen := int(binary.BigEndian.Uint16(msg[off+8 : off+10]))
		off += 10
		if off+rdlen > len(msg) {
			return 0, errors.New("invalid rdata")
		}
		if typeCode == 1 && rdlen == 4 {
			count++
		}
		off += rdlen
	}
	return count, nil
}

func printStats(s stats) {
	fmt.Println("--- Statistics ---")
	fmt.Printf("Total processed: %d\n", s.totalProcessed)
	fmt.Printf("Processing time: %.3fs\n", float64(s.processingNs)/1e9)
	fmt.Printf("Average latency: %.6fms\n", s.avgLatencyMs())
	fmt.Printf("Throughput: %.2f items/sec\n", s.throughput())
}

func main() {
	host, port, repeats, err := parseArgs()
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}

	conn, err := net.DialTimeout("udp", fmt.Sprintf("%s:%d", host, port), 2*time.Second)
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(10 * time.Second))

	start := time.Now()
	for i := 0; i < repeats; i++ {
		q := buildQuery(uint16(i+1), "example.com")
		if _, err := conn.Write(q); err != nil {
			fmt.Fprintln(os.Stderr, "Error:", err)
			os.Exit(1)
		}
		buf := make([]byte, 512)
		n, err := conn.Read(buf)
		if err != nil {
			fmt.Fprintln(os.Stderr, "Error:", err)
			os.Exit(1)
		}
		if _, err := parseARecordCount(buf[:n]); err != nil {
			fmt.Fprintln(os.Stderr, "Error:", err)
			os.Exit(1)
		}
	}

	printStats(stats{totalProcessed: uint64(repeats), processingNs: time.Since(start).Nanoseconds()})
}
