package main

import (
	"encoding/binary"
	"errors"
	"fmt"
	"os"
	"strconv"
	"time"
)

const (
	opLoadImm byte = 0x01
	opAdd     byte = 0x02
	opSub     byte = 0x03
	opMul     byte = 0x04
	opDiv     byte = 0x05
	opCmp     byte = 0x06
	opJmp     byte = 0x07
	opJz      byte = 0x08
	opPush    byte = 0x09
	opPop     byte = 0x0A
	opHalt    byte = 0x0B
)

type vm struct {
	regs  [8]uint64
	stack []uint64
	pc    int
	zero  bool
	code  []byte
}

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
	program := "/data/loop_sum.bin"
	iterations := 5000
	if len(os.Args) > 1 {
		program = os.Args[1]
	}
	if len(os.Args) > 2 {
		n, err := strconv.Atoi(os.Args[2])
		if err != nil || n < 1 {
			return "", 0, errors.New("iterations must be positive integer")
		}
		iterations = n
	}
	return program, iterations, nil
}

func readU32(code []byte, pc int) (uint32, error) {
	if pc+4 > len(code) {
		return 0, errors.New("unexpected EOF")
	}
	return binary.LittleEndian.Uint32(code[pc : pc+4]), nil
}

func (m *vm) run() (uint64, error) {
	var count uint64
	for m.pc < len(m.code) {
		op := m.code[m.pc]
		m.pc++
		count++
		switch op {
		case opLoadImm:
			if m.pc >= len(m.code) {
				return 0, errors.New("LOAD_IMM missing register")
			}
			reg := m.code[m.pc]
			m.pc++
			imm, err := readU32(m.code, m.pc)
			if err != nil {
				return 0, err
			}
			m.pc += 4
			if reg > 7 {
				return 0, errors.New("invalid register")
			}
			m.regs[reg] = uint64(imm)
		case opAdd, opSub, opMul, opDiv, opCmp:
			if m.pc+1 >= len(m.code) {
				return 0, errors.New("binary op missing operands")
			}
			a, b := m.code[m.pc], m.code[m.pc+1]
			m.pc += 2
			if a > 7 || b > 7 {
				return 0, errors.New("invalid register")
			}
			switch op {
			case opAdd:
				m.regs[a] += m.regs[b]
			case opSub:
				m.regs[a] -= m.regs[b]
			case opMul:
				m.regs[a] *= m.regs[b]
			case opDiv:
				if m.regs[b] == 0 {
					return 0, errors.New("division by zero")
				}
				m.regs[a] /= m.regs[b]
			case opCmp:
				m.zero = m.regs[a] == m.regs[b]
			}
		case opJmp, opJz:
			addr, err := readU32(m.code, m.pc)
			if err != nil {
				return 0, err
			}
			m.pc += 4
			if op == opJmp || (op == opJz && m.zero) {
				if int(addr) >= len(m.code) {
					return 0, errors.New("jump out of range")
				}
				m.pc = int(addr)
			}
		case opPush:
			reg := m.code[m.pc]
			m.pc++
			m.stack = append(m.stack, m.regs[reg])
		case opPop:
			if len(m.stack) == 0 {
				return 0, errors.New("stack underflow")
			}
			reg := m.code[m.pc]
			m.pc++
			m.regs[reg] = m.stack[len(m.stack)-1]
			m.stack = m.stack[:len(m.stack)-1]
		case opHalt:
			return count, nil
		default:
			return 0, fmt.Errorf("unknown opcode: 0x%02x", op)
		}
	}
	return count, nil
}

func printStats(s stats) {
	fmt.Println("--- Statistics ---")
	fmt.Printf("Total processed: %d\n", s.totalProcessed)
	fmt.Printf("Processing time: %.3fs\n", float64(s.processingNs)/1e9)
	fmt.Printf("Average latency: %.6fms\n", s.avgLatencyMs())
	fmt.Printf("Throughput: %.2f instructions/sec\n", s.throughput())
}

func main() {
	programPath, iterations, err := parseArgs()
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}
	code, err := os.ReadFile(programPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}
	start := time.Now()
	var total uint64
	for i := 0; i < iterations; i++ {
		m := vm{code: code}
		n, runErr := m.run()
		if runErr != nil {
			fmt.Fprintln(os.Stderr, "Error:", runErr)
			os.Exit(1)
		}
		total += n
	}
	printStats(stats{totalProcessed: total, processingNs: time.Since(start).Nanoseconds()})
}
