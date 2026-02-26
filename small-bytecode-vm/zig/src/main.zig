const std = @import("std");

const op_load_imm: u8 = 0x01;
const op_add: u8 = 0x02;
const op_sub: u8 = 0x03;
const op_mul: u8 = 0x04;
const op_div: u8 = 0x05;
const op_cmp: u8 = 0x06;
const op_jmp: u8 = 0x07;
const op_jz: u8 = 0x08;
const op_push: u8 = 0x09;
const op_pop: u8 = 0x0A;
const op_halt: u8 = 0x0B;

const Vm = struct {
    regs: [8]u64 = [_]u64{0} ** 8,
    stack: std.ArrayList(u64),
    pc: usize = 0,
    zero: bool = false,
    code: []const u8,

    fn init(code: []const u8) Vm {
        return .{ .stack = std.ArrayList(u64){}, .code = code, .pc = 0, .zero = false };
    }

    fn deinit(self: *Vm, allocator: std.mem.Allocator) void {
        self.stack.deinit(allocator);
    }

    fn readU32(self: *Vm) !u32 {
        if (self.pc + 4 > self.code.len) return error.UnexpectedEof;
        const value = std.mem.readInt(u32, self.code[self.pc .. self.pc + 4][0..4], .little);
        self.pc += 4;
        return value;
    }

    fn run(self: *Vm, allocator: std.mem.Allocator) !u64 {
        var count: u64 = 0;
        while (self.pc < self.code.len) {
            const op = self.code[self.pc];
            self.pc += 1;
            count += 1;
            switch (op) {
                op_load_imm => {
                    if (self.pc >= self.code.len) return error.InvalidInstruction;
                    const reg = self.code[self.pc];
                    self.pc += 1;
                    if (reg > 7) return error.InvalidRegister;
                    const imm = try self.readU32();
                    self.regs[reg] = imm;
                },
                op_add, op_sub, op_mul, op_div, op_cmp => {
                    if (self.pc + 1 >= self.code.len) return error.InvalidInstruction;
                    const a = self.code[self.pc];
                    const b = self.code[self.pc + 1];
                    self.pc += 2;
                    if (a > 7 or b > 7) return error.InvalidRegister;
                    switch (op) {
                        op_add => self.regs[a] += self.regs[b],
                        op_sub => self.regs[a] -= self.regs[b],
                        op_mul => self.regs[a] *= self.regs[b],
                        op_div => {
                            if (self.regs[b] == 0) return error.DivisionByZero;
                            self.regs[a] /= self.regs[b];
                        },
                        op_cmp => self.zero = self.regs[a] == self.regs[b],
                        else => unreachable,
                    }
                },
                op_jmp, op_jz => {
                    const addr = try self.readU32();
                    if (op == op_jmp or (op == op_jz and self.zero)) {
                        if (addr >= self.code.len) return error.JumpOutOfRange;
                        self.pc = addr;
                    }
                },
                op_push => {
                    if (self.pc >= self.code.len) return error.InvalidInstruction;
                    const reg = self.code[self.pc];
                    self.pc += 1;
                    if (reg > 7) return error.InvalidRegister;
                    try self.stack.append(allocator, self.regs[reg]);
                },
                op_pop => {
                    if (self.pc >= self.code.len) return error.InvalidInstruction;
                    const reg = self.code[self.pc];
                    self.pc += 1;
                    if (reg > 7) return error.InvalidRegister;
                    if (self.stack.items.len == 0) return error.StackUnderflow;
                    const value = self.stack.pop().?;
                    self.regs[reg] = value;
                },
                op_halt => return count,
                else => return error.UnknownOpcode,
            }
        }
        return count;
    }
};

const Stats = struct {
    total_processed: u64,
    processing_ns: u64,

    fn avgLatencyMs(self: Stats) f64 {
        if (self.total_processed == 0) return 0.0;
        return @as(f64, @floatFromInt(self.processing_ns)) / 1_000_000.0 / @as(f64, @floatFromInt(self.total_processed));
    }

    fn throughput(self: Stats) f64 {
        if (self.processing_ns == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_processed)) * 1_000_000_000.0 / @as(f64, @floatFromInt(self.processing_ns));
    }
};

fn parseArgs(allocator: std.mem.Allocator) !struct { program: []const u8, iterations: usize } {
    var args = std.process.args();
    _ = args.next();

    const program = if (args.next()) |p| try allocator.dupe(u8, p) else try allocator.dupe(u8, "/data/loop_sum.bin");
    const iterations = if (args.next()) |it| try std.fmt.parseInt(usize, it, 10) else 5000;
    return .{ .program = program, .iterations = iterations };
}

fn printStats(stats: Stats) void {
    std.debug.print("--- Statistics ---\n", .{});
    std.debug.print("Total processed: {d}\n", .{stats.total_processed});
    std.debug.print("Processing time: {d:.3}s\n", .{@as(f64, @floatFromInt(stats.processing_ns)) / 1_000_000_000.0});
    std.debug.print("Average latency: {d:.6}ms\n", .{stats.avgLatencyMs()});
    std.debug.print("Throughput: {d:.2} instructions/sec\n", .{stats.throughput()});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const cfg = try parseArgs(allocator);
    defer allocator.free(cfg.program);

    const code = try std.fs.cwd().readFileAlloc(allocator, cfg.program, 1024 * 1024);
    defer allocator.free(code);

    var timer = try std.time.Timer.start();
    var total: u64 = 0;

    for (0..cfg.iterations) |_| {
        var vm = Vm.init(code);
        defer vm.deinit(allocator);
        const n = try vm.run(allocator);
        total += n;
    }

    const s = Stats{ .total_processed = total, .processing_ns = timer.read() };
    printStats(s);
}
