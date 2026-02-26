package main

import (
	"encoding/binary"
	"errors"
	"fmt"
	"math"
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

func parseArgs() (string, int, error) {
	input := "/data/metrics.db"
	repeats := 1000
	if len(os.Args) > 1 {
		input = os.Args[1]
	}
	if len(os.Args) > 2 {
		n, err := strconv.Atoi(os.Args[2])
		if err != nil || n < 1 {
			return "", 0, errors.New("repeats must be positive integer")
		}
		repeats = n
	}
	return input, repeats, nil
}

// readVarint decodes a SQLite varint from data[off:].
// Returns (value, bytes consumed).
func readVarint(data []byte, off int) (uint64, int) {
	var n uint64
	for i := 0; i < 9; i++ {
		b := data[off+i]
		if i == 8 {
			return (n << 8) | uint64(b), 9
		}
		n = (n << 7) | uint64(b&0x7f)
		if b&0x80 == 0 {
			return n, i + 1
		}
	}
	return n, 9
}

// colSize returns the byte size of a SQLite record column given its serial type.
func colSize(t uint64) int {
	switch {
	case t == 0:
		return 0
	case t == 1:
		return 1
	case t == 2:
		return 2
	case t == 3:
		return 3
	case t == 4:
		return 4
	case t == 5:
		return 6
	case t == 6:
		return 8
	case t == 7:
		return 8
	case t == 8 || t == 9:
		return 0
	case t >= 12 && t%2 == 0:
		return int((t - 12) / 2)
	case t >= 13 && t%2 == 1:
		return int((t - 13) / 2)
	}
	return 0
}

// readIntCol reads a SQLite integer column value of the given serial type.
func readIntCol(data []byte, off int, t uint64) int64 {
	switch t {
	case 1:
		return int64(int8(data[off]))
	case 2:
		return int64(int16(binary.BigEndian.Uint16(data[off:])))
	case 3:
		v := uint32(data[off])<<16 | uint32(data[off+1])<<8 | uint32(data[off+2])
		if v&0x800000 != 0 {
			v |= 0xff000000
		}
		return int64(int32(v))
	case 4:
		return int64(int32(binary.BigEndian.Uint32(data[off:])))
	case 5:
		v := uint64(data[off])<<40 | uint64(data[off+1])<<32 |
			uint64(data[off+2])<<24 | uint64(data[off+3])<<16 |
			uint64(data[off+4])<<8 | uint64(data[off+5])
		if v&(1<<47) != 0 {
			v |= 0xffff000000000000
		}
		return int64(v)
	case 6:
		return int64(binary.BigEndian.Uint64(data[off:]))
	case 8:
		return 0
	case 9:
		return 1
	}
	return 0
}

func pageBase(pageNum, pageSize uint32) int {
	return int(uint64(pageNum-1) * uint64(pageSize))
}

func pageHeaderOff(pageNum, pageSize uint32) int {
	base := pageBase(pageNum, pageSize)
	if pageNum == 1 {
		base += 100 // skip SQLite file header
	}
	return base
}

// collectLeafPages does a DFS from pageNum, appending all leaf page numbers to leaves.
func collectLeafPages(data []byte, pageSize, pageNum uint32, leaves *[]uint32) {
	hOff := pageHeaderOff(pageNum, pageSize)
	pBase := pageBase(pageNum, pageSize)
	pageType := data[hOff]
	numCells := int(binary.BigEndian.Uint16(data[hOff+3:]))

	switch pageType {
	case 0x0d: // leaf table
		*leaves = append(*leaves, pageNum)
	case 0x05: // interior table — cell ptr array starts at hOff+12
		for i := 0; i < numCells; i++ {
			ptrOff := hOff + 12 + i*2
			cellOff := pBase + int(binary.BigEndian.Uint16(data[ptrOff:]))
			child := binary.BigEndian.Uint32(data[cellOff:])
			collectLeafPages(data, pageSize, child, leaves)
		}
		// rightmost child pointer at hOff+8
		rightmost := binary.BigEndian.Uint32(data[hOff+8:])
		collectLeafPages(data, pageSize, rightmost, leaves)
	}
}

// findTableRoot scans sqlite_schema (page 1) to find the root page of tableName.
func findTableRoot(data []byte, tableName string) (uint32, error) {
	hOff := 100 // B-tree header for page 1 starts after 100-byte file header
	numCells := int(binary.BigEndian.Uint16(data[hOff+3:]))

	for i := 0; i < numCells; i++ {
		ptrOff := hOff + 8 + i*2
		// Page 1 cell offsets are from start of file (page base = 0)
		cellOff := int(binary.BigEndian.Uint16(data[ptrOff:]))

		// Leaf cell: [payload_size varint][rowid varint][payload...]
		_, n := readVarint(data, cellOff)
		cellOff += n
		_, n = readVarint(data, cellOff)
		cellOff += n

		// Record header: [header_len varint][col_type varints...]
		hStart := cellOff
		hLen, n := readVarint(data, cellOff)
		cellOff += n
		hEnd := hStart + int(hLen)

		// sqlite_schema columns: type, name, tbl_name, rootpage, sql
		var types [5]uint64
		tmp := cellOff
		for j := 0; j < 5 && tmp < hEnd; j++ {
			t, tn := readVarint(data, tmp)
			types[j] = t
			tmp += tn
		}

		// Values start at hEnd
		valOff := hEnd
		valOff += colSize(types[0]) // skip col[0]: type TEXT

		// col[1]: name TEXT
		nameLen := colSize(types[1])
		name := string(data[valOff : valOff+nameLen])
		valOff += nameLen

		if name == tableName {
			valOff += colSize(types[2]) // skip col[2]: tbl_name TEXT
			root := readIntCol(data, valOff, types[3])
			return uint32(root), nil
		}
	}
	return 0, errors.New("table not found: " + tableName)
}

// query scans all leafPages repeats times and counts rows where cpu_pct > 80.0.
// Returns rowsScanned + matchingRows (consistent with other project benchmarks).
func query(data []byte, pageSize uint32, leafPages []uint32, repeats int) uint64 {
	var rowsScanned uint64
	var matchingRows uint64

	for r := 0; r < repeats; r++ {
		for _, pageNum := range leafPages {
			hOff := pageHeaderOff(pageNum, pageSize)
			pBase := pageBase(pageNum, pageSize)
			numCells := int(binary.BigEndian.Uint16(data[hOff+3:]))

			for i := 0; i < numCells; i++ {
				ptrOff := hOff + 8 + i*2
				cellOff := pBase + int(binary.BigEndian.Uint16(data[ptrOff:]))

				// skip payload_size varint
				_, n := readVarint(data, cellOff)
				cellOff += n
				// skip rowid varint
				_, n = readVarint(data, cellOff)
				cellOff += n

				// record header
				hStart := cellOff
				hLen, n := readVarint(data, cellOff)
				cellOff += n
				hEnd := hStart + int(hLen)

				// col[0] type (hostname TEXT)
				t0, n := readVarint(data, cellOff)
				cellOff += n
				// col[1] type (cpu_pct REAL=7) — not needed for offset calc, skip
				_, _ = cellOff, n

				// cpu_pct value is immediately after hostname value
				cpuOff := hEnd + colSize(t0)
				cpu := math.Float64frombits(binary.BigEndian.Uint64(data[cpuOff:]))

				rowsScanned++
				if cpu > 80.0 {
					matchingRows++
				}
			}
		}
	}

	return rowsScanned + matchingRows
}

func printStats(s stats) {
	fmt.Println("--- Statistics ---")
	fmt.Printf("Total processed: %d\n", s.totalProcessed)
	fmt.Printf("Processing time: %.3fs\n", float64(s.processingNs)/1e9)
	fmt.Printf("Average latency: %.6fms\n", s.avgLatencyMs())
	fmt.Printf("Throughput: %.2f items/sec\n", s.throughput())
}

func main() {
	input, repeats, err := parseArgs()
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}

	data, err := os.ReadFile(input)
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}
	if len(data) < 100 {
		fmt.Fprintln(os.Stderr, "Error: file too small")
		os.Exit(1)
	}

	rawPageSize := binary.BigEndian.Uint16(data[16:])
	var pageSize uint32
	if rawPageSize == 1 {
		pageSize = 65536
	} else {
		pageSize = uint32(rawPageSize)
	}

	rootPage, err := findTableRoot(data, "metrics")
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}

	var leafPages []uint32
	collectLeafPages(data, pageSize, rootPage, &leafPages)
	if len(leafPages) == 0 {
		fmt.Fprintln(os.Stderr, "Error: no leaf pages found")
		os.Exit(1)
	}

	start := time.Now()
	total := query(data, pageSize, leafPages, repeats)
	printStats(stats{totalProcessed: total, processingNs: time.Since(start).Nanoseconds()})
}
