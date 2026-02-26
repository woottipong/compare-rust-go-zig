use clap::Parser;
use std::fs;
use std::time::Instant;

const OP_LOAD_IMM: u8 = 0x01;
const OP_ADD: u8 = 0x02;
const OP_SUB: u8 = 0x03;
const OP_MUL: u8 = 0x04;
const OP_DIV: u8 = 0x05;
const OP_CMP: u8 = 0x06;
const OP_JMP: u8 = 0x07;
const OP_JZ: u8 = 0x08;
const OP_PUSH: u8 = 0x09;
const OP_POP: u8 = 0x0A;
const OP_HALT: u8 = 0x0B;

#[derive(Parser)]
struct Args {
    #[arg(default_value = "/data/loop_sum.bin")]
    program: String,
    #[arg(default_value_t = 5000)]
    iterations: usize,
}

struct Vm<'a> {
    regs: [u64; 8],
    stack: Vec<u64>,
    pc: usize,
    zero: bool,
    code: &'a [u8],
}

struct Stats {
    total_processed: u64,
    processing_ns: u128,
}

impl Stats {
    fn avg_latency_ms(&self) -> f64 {
        if self.total_processed == 0 { return 0.0; }
        self.processing_ns as f64 / 1_000_000.0 / self.total_processed as f64
    }
    fn throughput(&self) -> f64 {
        if self.processing_ns == 0 { return 0.0; }
        self.total_processed as f64 * 1_000_000_000.0 / self.processing_ns as f64
    }
}

impl<'a> Vm<'a> {
    fn read_u32(&self, pc: usize) -> Result<u32, String> {
        if pc + 4 > self.code.len() { return Err("unexpected EOF".to_string()); }
        Ok(u32::from_le_bytes(self.code[pc..pc + 4].try_into().unwrap()))
    }

    fn run(&mut self) -> Result<u64, String> {
        let mut count: u64 = 0;
        while self.pc < self.code.len() {
            let op = self.code[self.pc];
            self.pc += 1;
            count += 1;
            match op {
                OP_LOAD_IMM => {
                    let reg = *self.code.get(self.pc).ok_or("LOAD_IMM missing register")? as usize;
                    self.pc += 1;
                    let imm = self.read_u32(self.pc)?;
                    self.pc += 4;
                    if reg > 7 { return Err("invalid register".to_string()); }
                    self.regs[reg] = imm as u64;
                }
                OP_ADD | OP_SUB | OP_MUL | OP_DIV | OP_CMP => {
                    let a = *self.code.get(self.pc).ok_or("binary op missing operands")? as usize;
                    let b = *self.code.get(self.pc + 1).ok_or("binary op missing operands")? as usize;
                    self.pc += 2;
                    if a > 7 || b > 7 { return Err("invalid register".to_string()); }
                    match op {
                        OP_ADD => self.regs[a] += self.regs[b],
                        OP_SUB => self.regs[a] -= self.regs[b],
                        OP_MUL => self.regs[a] *= self.regs[b],
                        OP_DIV => {
                            if self.regs[b] == 0 { return Err("division by zero".to_string()); }
                            self.regs[a] /= self.regs[b];
                        }
                        OP_CMP => self.zero = self.regs[a] == self.regs[b],
                        _ => {}
                    }
                }
                OP_JMP | OP_JZ => {
                    let addr = self.read_u32(self.pc)? as usize;
                    self.pc += 4;
                    if op == OP_JMP || (op == OP_JZ && self.zero) {
                        if addr >= self.code.len() { return Err("jump out of range".to_string()); }
                        self.pc = addr;
                    }
                }
                OP_PUSH => {
                    let reg = *self.code.get(self.pc).ok_or("PUSH missing register")? as usize;
                    self.pc += 1;
                    self.stack.push(self.regs[reg]);
                }
                OP_POP => {
                    let reg = *self.code.get(self.pc).ok_or("POP missing register")? as usize;
                    self.pc += 1;
                    let value = self.stack.pop().ok_or("stack underflow")?;
                    self.regs[reg] = value;
                }
                OP_HALT => return Ok(count),
                _ => return Err(format!("unknown opcode: 0x{op:02x}")),
            }
        }
        Ok(count)
    }
}

fn print_stats(stats: &Stats) {
    println!("--- Statistics ---");
    println!("Total processed: {}", stats.total_processed);
    println!("Processing time: {:.3}s", stats.processing_ns as f64 / 1_000_000_000.0);
    println!("Average latency: {:.6}ms", stats.avg_latency_ms());
    println!("Throughput: {:.2} instructions/sec", stats.throughput());
}

fn main() {
    let args = Args::parse();
    let code = fs::read(&args.program).unwrap_or_else(|e| {
        eprintln!("Error: {e}");
        std::process::exit(1);
    });

    let start = Instant::now();
    let mut total: u64 = 0;
    for _ in 0..args.iterations {
        let mut vm = Vm { regs: [0; 8], stack: Vec::new(), pc: 0, zero: false, code: &code };
        let n = vm.run().unwrap_or_else(|e| {
            eprintln!("Error: {e}");
            std::process::exit(1);
        });
        total += n;
    }

    let stats = Stats { total_processed: total, processing_ns: start.elapsed().as_nanos() };
    print_stats(&stats);
}
