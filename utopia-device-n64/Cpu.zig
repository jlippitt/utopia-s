const fw = @import("framework");
const Device = @import("./Device.zig");
const Cp0 = @import("./Cpu/Cp0.zig");
const Cp1 = @import("./Cpu/Cp1.zig");
const alu = @import("./Cpu/alu.zig");
const control = @import("./Cpu/control.zig");
const memory = @import("./Cpu/memory.zig");
const mul_div = @import("./Cpu/mul_div.zig");
const shift = @import("./Cpu/shift.zig");

pub const Interrupt = Cp0.Interrupt;
pub const Exception = Cp0.Exception;

const Self = @This();

const cold_reset_vector = 0xbfc0_0000;

// zig fmt: off
pub const Register = enum(u5) {
    ZERO, AT, V0, V1, A0, A1, A2, A3,
    T0,   T1, T2, T3, T4, T5, T6, T7,
    S0,   S1, S2, S3, S4, S5, S6, S7,
    T8,   T9, K0, K1, GP, SP, FP, RA,
};
// zig fmt: on

pub const PipeState = enum {
    normal,
    branch,
    delay,
    except,
};

pub const IType = packed struct(u32) {
    imm: u16,
    rt: Register,
    rs: Register,
    opcode: u6,
};

pub const RType = packed struct(u32) {
    funct: u6,
    sa: u5,
    rd: Register,
    rt: Register,
    rs: Register,
    opcode: u6,
};

pub const BranchParams = struct {
    link: bool = false,
    likely: bool = false,
};

pub const Instruction = fn (self: *Self, word: u32) void;

pc: u32 = cold_reset_vector,
target_pc: u32 = 0,
pipe_state: PipeState = .normal,
regs: [32]u64 = @splat(0),
lo: u64 = 0,
hi: u64 = 0,
ll_bit: bool = false,
cp0: Cp0 = .init(),
cp1: Cp1 = .init(),

pub fn init() Self {
    return .{};
}

pub fn clearInterrupt(self: *Self, interrupt: Interrupt) void {
    self.cp0.clearInterrupt(interrupt);
}

pub fn raiseInterrupt(self: *Self, interrupt: Interrupt) void {
    self.cp0.raiseInterrupt(interrupt);
}

pub fn handleInterruptEvent(self: *Self) void {
    self.except(.interrupt);
}

pub fn handleTimerEvent(self: *Self) void {
    self.cp0.raiseInterrupt(.timer);
}

pub fn step(self: *Self) void {
    const address = self.mapAddress(self.pc, false) orelse return;
    const word = self.getDevice().read(address);

    const instr = decode(word);
    instr(self, word);

    if (self.pipe_state == .delay) {
        @branchHint(.unlikely);
        self.pc = self.target_pc;
    } else if (self.pipe_state != .except) {
        @branchHint(.likely);
        self.pc +%= 4;
    }

    if (self.pipe_state == .branch) {
        @branchHint(.unlikely);
        self.pipe_state = .delay;
    } else {
        self.pipe_state = .normal;
    }
}

pub fn get(self: *const Self, reg: Register) u64 {
    return self.regs[@intFromEnum(reg)];
}

pub fn set(self: *Self, reg: Register, value: u64) void {
    self.regs[@intFromEnum(reg)] = value;
    self.regs[@intFromEnum(Register.ZERO)] = 0;

    if (reg != Register.ZERO) {
        fw.log.trace("  {t}: {X:016}", .{ reg, value });
    }
}

pub fn mapAddress(self: *Self, vaddr: u32, store: bool) ?u32 {
    if ((vaddr & 0xc000_0000) == 0x8000_0000) {
        @branchHint(.likely);
        return vaddr & 0x1fff_ffff;
    }

    return self.cp0.mapAddress(vaddr, store) catch |err| {
        self.except(switch (err) {
            error.TlbModification => .{ .tlb_modification = vaddr },
            error.TlbMiss => if (store)
                .{ .tlb_miss_store = .{ .vaddr = vaddr, .invalid = false } }
            else
                .{ .tlb_miss_load = .{ .vaddr = vaddr, .invalid = false } },
            error.TlbInvalid => if (store)
                .{ .tlb_miss_store = .{ .vaddr = vaddr, .invalid = true } }
            else
                .{ .tlb_miss_load = .{ .vaddr = vaddr, .invalid = true } },
        });

        return null;
    };
}

pub fn readWord(self: *Self, paddr: u32) u32 {
    const value = self.getDevice().read(paddr);
    fw.log.trace("  [{X:08} => {X:08}]", .{ paddr, value });
    return value;
}

pub fn readDoubleWord(self: *Self, paddr: u32) u64 {
    const hi = self.readWord(paddr);
    const lo = self.readWord(paddr +% 4);
    return @as(u64, hi) << 32 | lo;
}

pub fn writeWord(self: *Self, paddr: u32, value: u32, mask: u32) void {
    fw.log.trace("  [{X:08} <= {X:08}]", .{ paddr, value });
    return self.getDevice().write(paddr, value, mask);
}

pub fn writeDoubleWord(self: *Self, paddr: u32, value: u64, mask: u64) void {
    self.writeWord(paddr, @truncate(value >> 32), @truncate(mask >> 32));
    self.writeWord(paddr +% 4, @truncate(value), @truncate(mask));
}

pub fn jump(self: *Self, target: u32) void {
    if (self.pipe_state == .delay) {
        @branchHint(.unlikely);
        fw.log.warn("Jump in CPU delay slot", .{});
        return;
    }

    self.target_pc = target;
    self.pipe_state = .branch;
}

pub fn branch(self: *Self, comptime params: BranchParams, offset: u32, taken: bool) void {
    if (comptime params.link) {
        self.link(.RA);
    }

    if (self.pipe_state == .delay) {
        @branchHint(.unlikely);
        fw.log.warn("Branch in CPU delay slot", .{});
        return;
    }

    if (taken) {
        fw.log.trace("  Branch taken", .{});
        self.target_pc = self.pc +% offset +% 4;
        self.pipe_state = .branch;
        return;
    }

    fw.log.trace("  Branch not taken", .{});

    if (comptime params.likely) {
        self.pc +%= 4;
        return;
    }

    self.target_pc = self.pc +% 8;
    self.pipe_state = .branch;
}

pub fn link(self: *Self, reg: Register) void {
    const address = if (self.pipe_state == .delay) blk: {
        fw.log.warn("Link in CPU delay slot", .{});
        break :blk self.target_pc +% 4;
    } else self.pc +% 8;

    self.set(reg, fw.num.signExtend(u64, address));
}

pub fn except(self: *Self, exception: Exception) void {
    self.pc = self.cp0.except(exception, self.pc, self.pipe_state == .delay);
    self.pipe_state = .except;
}

pub fn reserved(core: *Self, word: u32) void {
    fw.log.panic("Reserved instruction at {X:03}: {X:08}", .{ core.pc, word });
}

pub fn getDevice(self: *Self) *Device {
    return @alignCast(@fieldParentPtr("cpu", self));
}

pub fn getDeviceConst(self: *const Self) *const Device {
    return @alignCast(@fieldParentPtr("cpu", self));
}

fn decode(word: u32) *const Instruction {
    const opcode: u6 = @truncate(word >> 26);

    return switch (opcode) {
        0o00 => special_table[@as(u6, @truncate(word))],
        0o01 => regimm_table[@as(u5, @truncate(word >> 16))],
        0o20 => Cp0.cop0(word),
        0o21 => Cp1.cop1(word),
        else => main_table[opcode],
    };
}

fn cop2(self: *Self, word: u32) void {
    _ = word;
    self.except(.{ .coprocessor_unusable = 2 });
}

const main_table: [64]*const Instruction = blk: {
    var ops: [64]*const Instruction = @splat(reserved);
    ops[0o02] = control.j(.{});
    ops[0o03] = control.j(.{ .link = true });
    ops[0o04] = control.branchBinary(.BEQ, .{});
    ops[0o05] = control.branchBinary(.BNE, .{});
    ops[0o06] = control.branchUnary(.BLEZ, .{});
    ops[0o07] = control.branchUnary(.BGTZ, .{});
    ops[0o10] = alu.iTypeArithmetic(.ADD, .signed);
    ops[0o11] = alu.iTypeArithmetic(.ADD, .unsigned);
    ops[0o12] = alu.iTypeArithmetic(.SLT, .signed);
    ops[0o13] = alu.iTypeArithmetic(.SLT, .unsigned);
    ops[0o14] = alu.iTypeLogic(.AND);
    ops[0o15] = alu.iTypeLogic(.OR);
    ops[0o16] = alu.iTypeLogic(.XOR);
    ops[0o17] = alu.lui;
    ops[0o22] = cop2;
    ops[0o24] = control.branchBinary(.BEQ, .{ .likely = true });
    ops[0o25] = control.branchBinary(.BNE, .{ .likely = true });
    ops[0o26] = control.branchUnary(.BLEZ, .{ .likely = true });
    ops[0o27] = control.branchUnary(.BGTZ, .{ .likely = true });
    ops[0o30] = alu.iTypeArithmetic(.DADD, .signed);
    ops[0o31] = alu.iTypeArithmetic(.DADD, .unsigned);
    ops[0o32] = memory.load(.LDL);
    ops[0o33] = memory.load(.LDR);
    ops[0o40] = memory.load(.LB);
    ops[0o41] = memory.load(.LH);
    ops[0o42] = memory.load(.LWL);
    ops[0o43] = memory.load(.LW);
    ops[0o44] = memory.load(.LBU);
    ops[0o45] = memory.load(.LHU);
    ops[0o46] = memory.load(.LWR);
    ops[0o47] = memory.load(.LWU);
    ops[0o50] = memory.store(.SB);
    ops[0o51] = memory.store(.SH);
    ops[0o52] = memory.store(.SWL);
    ops[0o53] = memory.store(.SW);
    ops[0o54] = memory.store(.SDL);
    ops[0o55] = memory.store(.SDR);
    ops[0o56] = memory.store(.SWR);
    ops[0o57] = memory.cache;
    ops[0o60] = memory.load(.LL);
    ops[0o61] = Cp1.load(.LWC1);
    ops[0o64] = memory.load(.LLD);
    ops[0o65] = Cp1.load(.LDC1);
    ops[0o67] = memory.load(.LD);
    ops[0o70] = memory.store(.SC);
    ops[0o71] = Cp1.store(.SWC1);
    ops[0o74] = memory.store(.SCD);
    ops[0o75] = Cp1.store(.SDC1);
    ops[0o77] = memory.store(.SD);
    break :blk ops;
};

const special_table: [64]*const Instruction = blk: {
    var ops: [64]*const Instruction = @splat(reserved);
    ops[0o00] = shift.fixed(.SLL);
    ops[0o02] = shift.fixed(.SRL);
    ops[0o03] = shift.fixed(.SRA);
    ops[0o04] = shift.variable(.SLL);
    ops[0o06] = shift.variable(.SRL);
    ops[0o07] = shift.variable(.SRA);
    ops[0o10] = control.jr;
    ops[0o11] = control.jalr;
    ops[0o14] = control.syscall;
    ops[0o15] = control.break_;
    ops[0o17] = control.sync;
    ops[0o20] = mul_div.mfhi;
    ops[0o21] = mul_div.mthi;
    ops[0o22] = mul_div.mflo;
    ops[0o23] = mul_div.mtlo;
    ops[0o24] = shift.variable(.DSLL);
    ops[0o26] = shift.variable(.DSRL);
    ops[0o27] = shift.variable(.DSRA);
    ops[0o30] = mul_div.mulDiv(.MULT);
    ops[0o31] = mul_div.mulDiv(.MULTU);
    ops[0o32] = mul_div.mulDiv(.DIV);
    ops[0o33] = mul_div.mulDiv(.DIVU);
    ops[0o34] = mul_div.mulDiv(.DMULT);
    ops[0o35] = mul_div.mulDiv(.DMULTU);
    ops[0o36] = mul_div.mulDiv(.DDIV);
    ops[0o37] = mul_div.mulDiv(.DDIVU);
    ops[0o40] = alu.rTypeArithmetic(.ADD, .signed);
    ops[0o41] = alu.rTypeArithmetic(.ADD, .unsigned);
    ops[0o42] = alu.rTypeArithmetic(.SUB, .signed);
    ops[0o43] = alu.rTypeArithmetic(.SUB, .unsigned);
    ops[0o44] = alu.rTypeLogic(.AND);
    ops[0o45] = alu.rTypeLogic(.OR);
    ops[0o46] = alu.rTypeLogic(.XOR);
    ops[0o47] = alu.rTypeLogic(.NOR);
    ops[0o52] = alu.rTypeArithmetic(.SLT, .signed);
    ops[0o53] = alu.rTypeArithmetic(.SLT, .unsigned);
    ops[0o54] = alu.rTypeArithmetic(.DADD, .signed);
    ops[0o55] = alu.rTypeArithmetic(.DADD, .unsigned);
    ops[0o56] = alu.rTypeArithmetic(.DSUB, .signed);
    ops[0o57] = alu.rTypeArithmetic(.DSUB, .unsigned);
    ops[0o60] = control.rTypeTrap(.TGE, .signed);
    ops[0o61] = control.rTypeTrap(.TGE, .unsigned);
    ops[0o62] = control.rTypeTrap(.TLT, .signed);
    ops[0o63] = control.rTypeTrap(.TLT, .unsigned);
    ops[0o64] = control.rTypeTrap(.TEQ, .signed);
    ops[0o66] = control.rTypeTrap(.TNE, .signed);
    ops[0o70] = shift.fixed(.DSLL);
    ops[0o72] = shift.fixed(.DSRL);
    ops[0o73] = shift.fixed(.DSRA);
    ops[0o74] = shift.fixed32(.DSLL);
    ops[0o76] = shift.fixed32(.DSRL);
    ops[0o77] = shift.fixed32(.DSRA);
    break :blk ops;
};

const regimm_table: [32]*const Instruction = blk: {
    var ops: [32]*const Instruction = @splat(reserved);
    ops[0o00] = control.branchUnary(.BLTZ, .{});
    ops[0o01] = control.branchUnary(.BGEZ, .{});
    ops[0o02] = control.branchUnary(.BLTZ, .{ .likely = true });
    ops[0o03] = control.branchUnary(.BGEZ, .{ .likely = true });
    ops[0o10] = control.iTypeTrap(.TGE, .signed);
    ops[0o11] = control.iTypeTrap(.TGE, .unsigned);
    ops[0o12] = control.iTypeTrap(.TLT, .signed);
    ops[0o13] = control.iTypeTrap(.TLT, .unsigned);
    ops[0o14] = control.iTypeTrap(.TEQ, .signed);
    ops[0o16] = control.iTypeTrap(.TNE, .signed);
    ops[0o20] = control.branchUnary(.BLTZ, .{ .link = true });
    ops[0o21] = control.branchUnary(.BGEZ, .{ .link = true });
    ops[0o22] = control.branchUnary(.BLTZ, .{ .link = true, .likely = true });
    ops[0o23] = control.branchUnary(.BGEZ, .{ .link = true, .likely = true });
    break :blk ops;
};
