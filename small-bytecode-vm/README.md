# Small Bytecode VM

Virtual Machine ขนาดเล็กสำหรับรัน bytecode เพื่อเปรียบเทียบ Go / Rust / Zig ในงาน interpreter loop, memory model และ instruction execution speed.

## วัตถุประสงค์

- **Interpreter Loop**: เปรียบเทียบ `switch`/`match` dispatch ของแต่ละภาษา
- **Memory Model**: stack ที่ grow on demand, registers บน stack frame
- **Error Handling**: Go errors, Rust Result, Zig error unions
- **Bytecode Parsing**: Little-endian u32 operand decoding

## ทักษะที่ฝึก

- **Go**: `switch` dispatch, slice stack, `encoding/binary`
- **Rust**: `match` + `impl` + lifetime `'a` สำหรับ borrowed bytecode
- **Zig**: `switch` + `comptime`, unmanaged `ArrayList`, error unions

## Directory Structure

```text
small-bytecode-vm/
├── go/
│   ├── main.go         # VM + dispatcher
│   ├── go.mod
│   └── Dockerfile
├── rust/
│   ├── src/main.rs     # VM + dispatcher
│   ├── Cargo.toml      # dependencies: clap
│   └── Dockerfile
├── zig/
│   ├── src/main.zig    # VM + dispatcher
│   ├── build.zig       # Zig 0.15+ build system
│   ├── build.zig.zon
│   └── Dockerfile
├── test-data/
│   ├── loop_sum.bin    # Σ(1..100) ด้วย register loop
│   ├── arithmetic.bin  # ADD/SUB/MUL/DIV operations
│   └── branch.bin      # CMP + JMP/JZ branching
├── benchmark/
│   └── run.sh
└── README.md
```

## Instruction Set

| Opcode | Mnemonic   | Encoding                     | Description                       |
|--------|------------|------------------------------|-----------------------------------|
| `0x01` | `LOAD_IMM` | `[reg:u8][imm:u32le]`        | load 32-bit immediate into reg    |
| `0x02` | `ADD`      | `[dst:u8][src:u8]`           | dst += src                        |
| `0x03` | `SUB`      | `[dst:u8][src:u8]`           | dst -= src                        |
| `0x04` | `MUL`      | `[dst:u8][src:u8]`           | dst *= src                        |
| `0x05` | `DIV`      | `[dst:u8][src:u8]`           | dst /= src (error on div-by-zero) |
| `0x06` | `CMP`      | `[a:u8][b:u8]`               | zero_flag = (a == b)              |
| `0x07` | `JMP`      | `[addr:u32le]`               | unconditional jump                |
| `0x08` | `JZ`       | `[addr:u32le]`               | jump if zero_flag set             |
| `0x09` | `PUSH`     | `[reg:u8]`                   | push reg to stack                 |
| `0x0A` | `POP`      | `[reg:u8]`                   | pop stack into reg                |
| `0x0B` | `HALT`     | —                            | stop execution                    |

- 8 general-purpose registers: r0–r7 (u64)
- Stack: dynamic, grows on demand
- Zero flag: set by `CMP`, read by `JZ`

## Test Programs (test-data/)

### loop_sum.bin — 44 bytes

Computes Σ(1..100) = 5050 using a register loop:

```asm
LOAD_IMM r0, 0      ; sum = 0
LOAD_IMM r1, 0      ; counter = 0
LOAD_IMM r2, 100    ; limit = 100
LOAD_IMM r3, 1      ; step = 1
loop:
  ADD  r1, r3       ; counter++
  ADD  r0, r1       ; sum += counter
  CMP  r1, r2       ; zero = (counter == 100)?
  JZ   halt         ; if done → halt
  JMP  loop         ; else loop
halt:
  HALT
```

Instructions per VM run: **504** (4 init + 100 × 5 loop body = 504)

### arithmetic.bin — 34 bytes

Tests ADD, MUL, DIV with immediate-loaded operands.

### branch.bin — 38 bytes

Tests CMP + JZ + JMP branching with two code paths.

## Dependencies

### macOS
- Go 1.25+, Rust 1.85+, Zig 0.15.2+, Docker Desktop

### Linux (Docker)
- `golang:1.25-bookworm`, `rust:1.85-bookworm`, `debian:bookworm-slim` (Zig)

## Build & Run

### Local

```bash
# Go
cd go && unset GOROOT && go build -o ../bin/bvm-go .

# Rust
cd rust && cargo build --release

# Zig
cd zig && zig build -Doptimize=ReleaseFast
```

### Docker

```bash
docker build -t bvm-go go/
docker build -t bvm-rust rust/
docker build -t bvm-zig zig/
```

### Run (ต้อง mount test-data)

```bash
# Default: loop_sum.bin, 1,000,000 iterations
docker run --rm -v "$PWD/test-data:/data:ro" bvm-go
docker run --rm -v "$PWD/test-data:/data:ro" bvm-rust
docker run --rm -v "$PWD/test-data:/data:ro" bvm-zig

# Custom program + iterations
docker run --rm -v "$PWD/test-data:/data:ro" bvm-go /data/arithmetic.bin 500000
```

## Benchmark

```bash
bash benchmark/run.sh
```

ผลลัพธ์ auto-save ลง `benchmark/results/small_bytecode_vm_<timestamp>.txt`

รัน 5 ครั้ง: 1 warm-up + 4 measured แสดง Avg/Min/Max throughput และ binary size

## ผลการวัด (Benchmark Results)

วัดด้วย 1,000,000 iterations บน `loop_sum.bin` (504 instructions/run ≈ 504M total instructions),
Docker-based, Apple M-series

```
╔════════════════════════════╗
║ Small Bytecode VM Bench    ║
╚════════════════════════════╝

─ Go ─────────────────────
  Warm-up: 222808354.77 instructions/sec
  Run 1: 211856343.28 instructions/sec
  Run 2: 228531098.69 instructions/sec
  Run 3: 165711548.76 instructions/sec
  Run 4: 169224910.94 instructions/sec
  Avg: 193830975.41 instructions/sec
  Min: 165711549 instructions/sec
  Max: 228531099 instructions/sec

─ Rust ─────────────────────
  Warm-up: 455288151.55 instructions/sec
  Run 1: 481300370.47 instructions/sec
  Run 2: 406510608.74 instructions/sec
  Run 3: 432309626.08 instructions/sec
  Run 4: 498548599.40 instructions/sec
  Avg: 454667301.17 instructions/sec
  Min: 406510609 instructions/sec
  Max: 498548599 instructions/sec

─ Zig ─────────────────────
  Warm-up: 538509794.35 instructions/sec
  Run 1: 569773998.13 instructions/sec
  Run 2: 575811791.80 instructions/sec
  Run 3: 578883334.53 instructions/sec
  Run 4: 574098721.51 instructions/sec
  Avg: 574641961.49 instructions/sec
  Min: 569773998 instructions/sec
  Max: 578883335 instructions/sec

─ Binary Size ───────────────
  Go: 1.62MB
  Rust: 836.00KB
  Zig: 2.17MB
```

## สรุปผลเปรียบเทียบ

| Metric | Go | Rust | Zig | Winner |
|--------|-----|------|-----|---------|
| **Throughput (avg)** | 193M instr/sec | 454M instr/sec | **574M instr/sec** | **Zig** |
| **Throughput (min)** | 165M instr/sec | 406M instr/sec | **569M instr/sec** | **Zig** |
| **Variance** | ~38% | ~23% | **~1.6%** | **Zig** |
| **Binary Size** | 1.62MB | **836KB** | 2.17MB | **Rust** |
| **Code Simplicity** | High | Medium | Medium | **Go** |

## Key Insights

1. **Zig ชนะทั้ง throughput และ stability** — 574M instructions/sec เร็วกว่า Rust 1.26x และเร็วกว่า Go 2.96x พร้อม variance เพียง 1.6% (ดีที่สุดในสามภาษา) เพราะ `ReleaseFast` optimize dispatch loop ได้มากกว่า
2. **Rust อยู่ตรงกลาง** — 454M instructions/sec, variance ~23% เกิดจาก Docker VM CPU frequency scaling บน Apple Silicon; Rust's `match` + ownership เพิ่ม bounds check overhead เล็กน้อย
3. **Go ช้าที่สุด** — 193M instructions/sec, variance ~38% เกิดจาก GC runtime overhead แม้ไม่มี GC pause จริงๆ ในช่วงวัด, goroutine scheduler และ runtime overhead ทำให้ผลไม่สม่ำเสมอ
4. **Rust ชนะ binary size** — 836KB (stripped) เล็กกว่า Zig (2.17MB, GPA debug machinery) และ Go (1.62MB, runtime)
5. **Iteration count สำคัญมาก** — ต้องรัน ≥500,000 iterations เพื่อให้แต่ละ Docker run ใช้เวลา ≥1 วินาที; การใช้ 5,000 iterations ทำให้แต่ละ run ใช้แค่ ~10ms → variance สูงถึง 2.7x

## Technical Notes

### Go
- `switch byte` dispatch — Go compiler ไม่ทำ jump table สำหรับ sparse opcodes → linear scan หรือ hashed jump table
- Stack เป็น `[]uint64` nil slice — grow on demand ด้วย `append`
- `encoding/binary.LittleEndian.Uint32` — safe boundary check

### Rust
- `match u8` — Rust compiler มักทำ jump table เมื่อ opcode dense ≥ threshold
- Lifetime `'a` บน `Vm<'a>` — zero-copy reference to bytecode slice (ไม่ clone)
- Error handling ด้วย `?` operator + `ok_or()`

### Zig
- `switch` comptime — Zig compiler ทำ jump table อัตโนมัติ + dead branch elimination
- `std.ArrayList` unmanaged — allocator ส่งผ่าน parameter ทุก call ไม่เก็บใน struct
- `std.mem.readInt(u32, ..., .little)` — compile-time endian selection
- `ReleaseFast` — ปิด safety checks ทั้งหมด (overflow, bounds, undefined behavior)

### ทำไม Zig เร็วกว่า

Zig ReleaseFast ปิด:
- Array bounds checking (Rust/Go ยังคง check ใน safe code)
- Integer overflow detection
- Stack overflow detection

ทำให้ inner dispatch loop บน ARM64 เป็น tight branch-table jump ล้วนๆ
