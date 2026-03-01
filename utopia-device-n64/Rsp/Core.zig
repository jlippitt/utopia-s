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
    self.set(reg, if (self.pipe_state == .delay) self.target_pc +% 4 else self.pc +% 8);
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
    switch (@as(u6, @truncate(word >> 26))) {
        0o00 => special(core, word),
        0o01 => regImm(core, word),
        0o02 => control.j(.{}, core, word),
        0o03 => control.j(.{ .link = true }, core, word),
        0o04 => control.branchBinary(.BEQ, .{}, core, word),
        0o05 => control.branchBinary(.BNE, .{}, core, word),
        0o06 => control.branchUnary(.BLEZ, .{}, core, word),
        0o07 => control.branchUnary(.BGTZ, .{}, core, word),
        0o10 => alu.iTypeArithmetic(.ADD, .signed, core, word),
        0o11 => alu.iTypeArithmetic(.ADD, .unsigned, core, word),
        0o12 => alu.iTypeArithmetic(.SLT, .signed, core, word),
        0o13 => alu.iTypeArithmetic(.SLT, .unsigned, core, word),
        0o14 => alu.iTypeLogic(.AND, core, word),
        0o15 => alu.iTypeLogic(.OR, core, word),
        0o16 => alu.iTypeLogic(.XOR, core, word),
        0o17 => alu.lui(core, word),
        0o20 => cp0.cop0(core, word),
        0o22 => Cp2.cop2(core, word),
        0o40 => memory.load(.LB, core, word),
        0o41 => memory.load(.LH, core, word),
        0o43 => memory.load(.LW, core, word),
        0o44 => memory.load(.LBU, core, word),
        0o45 => memory.load(.LHU, core, word),
        0o47 => memory.load(.LWU, core, word),
        0o50 => memory.store(.SB, core, word),
        0o51 => memory.store(.SH, core, word),
        0o53 => memory.store(.SW, core, word),
        0o62 => Cp2.lwc2(core, word),
        0o72 => Cp2.swc2(core, word),
        else => |opcode| fw.log.todo("RSP opcode: {o:02}", .{opcode}),
    }
}

fn special(core: *Self, word: u32) void {
    switch (@as(u6, @truncate(word))) {
        0o00 => shift.fixed(.SLL, core, word),
        0o02 => shift.fixed(.SRL, core, word),
        0o03 => shift.fixed(.SRA, core, word),
        0o04 => shift.variable(.SLL, core, word),
        0o06 => shift.variable(.SRL, core, word),
        0o07 => shift.variable(.SRA, core, word),
        0o10 => control.jr(core, word),
        0o11 => control.jalr(core, word),
        0o15 => control.break_(core, word),
        0o40 => alu.rTypeArithmetic(.ADD, .signed, core, word),
        0o41 => alu.rTypeArithmetic(.ADD, .unsigned, core, word),
        0o42 => alu.rTypeArithmetic(.SUB, .signed, core, word),
        0o43 => alu.rTypeArithmetic(.SUB, .unsigned, core, word),
        0o44 => alu.rTypeLogic(.AND, core, word),
        0o45 => alu.rTypeLogic(.OR, core, word),
        0o46 => alu.rTypeLogic(.XOR, core, word),
        0o47 => alu.rTypeLogic(.NOR, core, word),
        0o52 => alu.rTypeArithmetic(.SLT, .signed, core, word),
        0o53 => alu.rTypeArithmetic(.SLT, .unsigned, core, word),
        else => |funct| fw.log.todo("RSP Special funct: {o:02}", .{funct}),
    }
}

fn regImm(core: *Self, word: u32) void {
    switch (@as(u5, @truncate(word >> 16))) {
        0o00 => control.branchUnary(.BLTZ, .{}, core, word),
        0o01 => control.branchUnary(.BGEZ, .{}, core, word),
        0o20 => control.branchUnary(.BLTZ, .{ .link = true }, core, word),
        0o21 => control.branchUnary(.BGEZ, .{ .link = true }, core, word),
        else => |rt| fw.log.todo("RSP RegImm rt: {o:02}", .{rt}),
    }
}
