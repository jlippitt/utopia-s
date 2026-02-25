const fw = @import("framework");
const Cp0 = @import("./Cpu/Cp0.zig");
const alu = @import("./Cpu/alu.zig");
const control = @import("./Cpu/control.zig");
const memory = @import("./Cpu/memory.zig");
const mul_div = @import("./Cpu/mul_div.zig");
const shift = @import("./Cpu/shift.zig");

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

pub const Bus = struct {
    read: fn (self: *Self, address: u32) u32,
    write: fn (self: *Self, address: u32, value: u32, mask: u32) void,
};

pc: u32 = cold_reset_vector,
target_pc: u32 = 0,
pipe_state: PipeState = .normal,
regs: [32]u64 = @splat(0),
lo: u64 = 0,
hi: u64 = 0,
cp0: Cp0 = .init(),

pub fn init() Self {
    return .{};
}

pub fn step(self: *Self, comptime bus: Bus) void {
    const word = bus.read(self, self.mapAddress(self.pc) orelse return);

    dispatch(bus, self, word);

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

pub fn mapAddress(self: *Self, vaddr: u32) ?u32 {
    _ = self;

    if ((vaddr & 0xc000_0000) == 0x8000_0000) {
        @branchHint(.likely);
        return vaddr & 0x1fff_ffff;
    }

    fw.log.todo("TLB lookups", .{});
}

pub fn readWord(self: *Self, comptime bus: Bus, paddr: u32) u32 {
    const value = bus.read(self, paddr);
    fw.log.trace("  [{X:08} => {X:08}]", .{ paddr, value });
    return value;
}

pub fn writeWord(self: *Self, comptime bus: Bus, paddr: u32, value: u32, mask: u32) void {
    fw.log.trace("  [{X:08} <= {X:08}]", .{ paddr, value });
    return bus.write(self, paddr, value, mask);
}

pub fn jump(self: *Self, target: u32) void {
    if (self.pipe_state == .delay) {
        @branchHint(.unlikely);
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
    const address = if (self.pipe_state == .delay) self.target_pc +% 4 else self.pc +% 8;
    self.set(reg, fw.num.signExtend(u64, address));
}

fn dispatch(comptime bus: Bus, core: *Self, word: u32) void {
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
        0o20 => Cp0.cop0(bus, core, word),
        0o24 => control.branchBinary(.BEQ, .{ .likely = true }, core, word),
        0o25 => control.branchBinary(.BNE, .{ .likely = true }, core, word),
        0o26 => control.branchUnary(.BLEZ, .{ .likely = true }, core, word),
        0o27 => control.branchUnary(.BGTZ, .{ .likely = true }, core, word),
        0o30 => alu.iTypeArithmetic(.DADD, .signed, core, word),
        0o31 => alu.iTypeArithmetic(.DADD, .unsigned, core, word),
        0o43 => memory.load(.LW, bus, core, word),
        0o47 => memory.load(.LWU, bus, core, word),
        0o53 => memory.store(.SW, bus, core, word),
        0o57 => memory.cache(core, word),
        else => |opcode| fw.log.todo("CPU opcode: {o:02}", .{opcode}),
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
        0o20 => mul_div.mfhi(core, word),
        0o21 => mul_div.mthi(core, word),
        0o22 => mul_div.mflo(core, word),
        0o23 => mul_div.mtlo(core, word),
        0o24 => shift.variable(.DSLL, core, word),
        0o26 => shift.variable(.DSRL, core, word),
        0o27 => shift.variable(.DSRA, core, word),
        0o30 => mul_div.mulDiv(.MULT, core, word),
        0o31 => mul_div.mulDiv(.MULTU, core, word),
        0o34 => mul_div.mulDiv(.DMULT, core, word),
        0o35 => mul_div.mulDiv(.DMULTU, core, word),
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
        0o54 => alu.rTypeArithmetic(.DADD, .signed, core, word),
        0o55 => alu.rTypeArithmetic(.DADD, .unsigned, core, word),
        0o56 => alu.rTypeArithmetic(.DSUB, .signed, core, word),
        0o57 => alu.rTypeArithmetic(.DSUB, .unsigned, core, word),
        0o70 => shift.fixed(.DSLL, core, word),
        0o72 => shift.fixed(.DSRL, core, word),
        0o73 => shift.fixed(.DSRA, core, word),
        0o74 => shift.fixed32(.DSLL, core, word),
        0o76 => shift.fixed32(.DSRL, core, word),
        0o77 => shift.fixed32(.DSRA, core, word),
        else => |funct| fw.log.todo("CPU Special funct: {o:02}", .{funct}),
    }
}

fn regImm(core: *Self, word: u32) void {
    switch (@as(u5, @truncate(word >> 16))) {
        0o00 => control.branchUnary(.BLTZ, .{}, core, word),
        0o01 => control.branchUnary(.BGEZ, .{}, core, word),
        0o02 => control.branchUnary(.BLTZ, .{ .likely = true }, core, word),
        0o03 => control.branchUnary(.BGEZ, .{ .likely = true }, core, word),
        0o20 => control.branchUnary(.BLTZ, .{ .link = true }, core, word),
        0o21 => control.branchUnary(.BGEZ, .{ .link = true }, core, word),
        0o22 => control.branchUnary(.BLTZ, .{ .link = true, .likely = true }, core, word),
        0o23 => control.branchUnary(.BGEZ, .{ .link = true, .likely = true }, core, word),
        else => |rt| fw.log.todo("CPU RegImm rt: {o:02}", .{rt}),
    }
}
