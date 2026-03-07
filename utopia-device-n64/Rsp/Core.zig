const std = @import("std");
const fw = @import("framework");
const Rsp = @import("../Rsp.zig");
const Cp2 = @import("./Cp2.zig");
const alu = @import("./alu.zig");
const control = @import("./control.zig");
const cp0 = @import("./cp0.zig");
const memory = @import("./memory.zig");
const shift = @import("./shift.zig");

const Self = @This();

// zig fmt: off
pub const Register = enum(u5) {
    ZERO, AT, V0, V1, A0, A1, A2, A3,
    T0,   T1, T2, T3, T4, T5, T6, T7,
    S0,   S1, S2, S3, S4, S5, S6, S7,
    T8,   T9, K0, K1, GP, SP, FP, RA,
};
// zig fmt: on

pub const Cp0Register = cp0.Register;

pub const PipeState = enum {
    normal,
    branch,
    delay,
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
};

pub const Instruction = fn (self: *Self, word: u32) void;

pc: u12 = 0,
target_pc: u12 = 0,
pipe_state: PipeState = .normal,
regs: [32]u32 = @splat(0),
cp2: Cp2,

pub fn init() Self {
    return .{
        .cp2 = Cp2.init(),
    };
}

pub fn readPc(self: *const Self) u12 {
    return self.pc;
}

pub fn writePc(self: *Self, value: u12, mask: u12) void {
    fw.num.writeMasked(u12, &self.pc, value, mask & 0xffc);
    fw.log.debug("RSP PC: {X:08}", .{self.pc});
}

pub fn step(self: *Self) void {
    const word = self.getRspConst().readInstruction(self.pc);

    dispatch(self, word);

    if (self.pipe_state == .delay) {
        @branchHint(.unlikely);
        self.pc = self.target_pc;
    } else {
        self.pc +%= 4;
    }

    if (self.pipe_state == .branch) {
        @branchHint(.unlikely);
        self.pipe_state = .delay;
    } else {
        self.pipe_state = .normal;
    }
}

pub fn get(self: *const Self, reg: Register) u32 {
    return self.regs[@intFromEnum(reg)];
}

pub fn set(self: *Self, reg: Register, value: u32) void {
    self.regs[@intFromEnum(reg)] = value;
    self.regs[@intFromEnum(Register.ZERO)] = 0;

    if (reg != Register.ZERO) {
        fw.log.trace("  {t}: {X:08}", .{ reg, value });
    }
}

pub fn readData(self: *Self, comptime T: type, address: u12) T {
    const value = self.getRspConst().readData(T, address);
    fw.log.trace("  [{X:03} => {s}]", .{ address, formatHex(value) });
    return value;
}

pub fn readDataAligned(self: *Self, comptime T: type, address: u12) T {
    std.debug.assert((address & (@sizeOf(T) - 1)) == 0);
    const value = self.getRspConst().readDataAligned(T, address);
    fw.log.trace("  [{X:03} => {s}]", .{ address, formatHex(value) });
    return value;
}

pub fn writeData(self: *Self, comptime T: type, address: u12, value: T) void {
    fw.log.trace("  [{X:03} <= {s}]", .{ address, formatHex(value) });
    return self.getRsp().writeData(T, address, value);
}

pub fn writeDataAligned(self: *Self, comptime T: type, address: u12, value: T) void {
    std.debug.assert((address & (@sizeOf(T) - 1)) == 0);
    fw.log.trace("  [{X:03} <= {s}]", .{ address, formatHex(value) });
    return self.getRsp().writeDataAligned(T, address, value);
}

pub fn writeDataAlignedMasked(
    self: *Self,
    comptime T: type,
    address: u12,
    value: T,
    mask: T,
) void {
    std.debug.assert((address & (@sizeOf(T) - 1)) == 0);
    fw.log.trace("  [{X:03} <= {s}]", .{ address, formatHex(value) });
    return self.getRsp().writeDataAlignedMasked(T, address, value, mask);
}

pub fn jump(self: *Self, target: u12) void {
    if (self.pipe_state == .delay) {
        @branchHint(.unlikely);
        fw.log.warn("Jump in RSP delay slot", .{});
        return;
    }

    self.target_pc = target;
    self.pipe_state = .branch;
}

pub fn branch(self: *Self, comptime params: BranchParams, offset: u12, taken: bool) void {
    if (comptime params.link) {
        self.link(.RA);
    }

    if (self.pipe_state == .delay) {
        @branchHint(.unlikely);
        fw.log.warn("Branch in RSP delay slot", .{});
        return;
    }

    if (taken) {
        fw.log.trace("  Branch taken", .{});
        self.target_pc = self.pc +% offset +% 4;
        self.pipe_state = .branch;
        return;
    }

    fw.log.trace("  Branch not taken", .{});
    self.target_pc = self.pc +% 8;
    self.pipe_state = .branch;
}

pub fn link(self: *Self, reg: Register) void {
    const address = if (self.pipe_state == .delay) blk: {
        fw.log.warn("Link in RSP delay slot", .{});
        break :blk self.target_pc +% 4;
    } else self.pc +% 8;

    self.set(reg, address);
}

pub fn getRsp(self: *Self) *Rsp {
    return @alignCast(@fieldParentPtr("core", self));
}

pub fn getRspConst(self: *const Self) *const Rsp {
    return @alignCast(@fieldParentPtr("core", self));
}

fn formatHex(value: anytype) [@typeInfo(@TypeOf(value)).int.bits >> 2]u8 {
    const size = comptime @typeInfo(@TypeOf(value)).int.bits >> 3;
    const bytes: [size]u8 = @bitCast(@byteSwap(value));
    return std.fmt.bytesToHex(bytes, .upper);
}

fn dispatch(core: *Self, word: u32) void {
    const opcode: u6 = @truncate(word >> 26);

    const instr: *const Instruction = if (opcode == 0)
        special_table[@as(u6, @truncate(word))]
    else if (opcode == 1)
        regimm_table[@as(u5, @truncate(word >> 16))]
    else
        main_table[opcode];

    instr(core, word);
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
    ops[0o20] = cp0.cop0;
    ops[0o22] = Cp2.cop2;
    ops[0o40] = memory.load(.LB);
    ops[0o41] = memory.load(.LH);
    ops[0o43] = memory.load(.LW);
    ops[0o44] = memory.load(.LBU);
    ops[0o45] = memory.load(.LHU);
    ops[0o47] = memory.load(.LWU);
    ops[0o50] = memory.store(.SB);
    ops[0o51] = memory.store(.SH);
    ops[0o53] = memory.store(.SW);
    ops[0o62] = Cp2.lwc2;
    ops[0o72] = Cp2.swc2;
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
    ops[0o15] = control.break_;
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
    break :blk ops;
};

const regimm_table: [32]*const Instruction = blk: {
    var ops: [32]*const Instruction = @splat(reserved);
    ops[0o00] = control.branchUnary(.BLTZ, .{});
    ops[0o01] = control.branchUnary(.BGEZ, .{});
    ops[0o20] = control.branchUnary(.BLTZ, .{ .link = true });
    ops[0o21] = control.branchUnary(.BGEZ, .{ .link = true });
    break :blk ops;
};

fn reserved(core: *Self, word: u32) void {
    fw.log.panic("Reserved instruction at {X:03}: {X:08}", .{ core.pc, word });
}
