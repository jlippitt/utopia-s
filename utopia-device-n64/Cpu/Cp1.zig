const std = @import("std");
const fw = @import("framework");
const Core = @import("../Cpu.zig");
const arithmetic = @import("./Cp1/arithmetic.zig");
const compare = @import("./Cp1/compare.zig");
const convert = @import("./Cp1/convert.zig");
const memory = @import("./Cp1/memory.zig");

pub const load = memory.load;
pub const store = memory.store;

// zig fmt: off
const Register = enum(u5) {
    F0,  F1,  F2,  F3,  F4,  F5,  F6,  F7,
    F8,  F9,  F10, F11, F12, F13, F14, F15,
    F16, F17, F18, F19, F20, F21, F22, F23,
    F24, F25, F26, F27, F28, F29, F30, F31,
};
// zig fmt: on

// zig fmt: off
const ControlRegister = enum(u5) {
    Revision,  FCR1,  FCR2,  FCR3,  FCR4,  FCR5,  FCR6,  FCR7,
    FCR8,  FCR9,  FCR10, FCR11, FCR12, FCR13, FCR14, FCR15,
    FCR16, FCR17, FCR18, FCR19, FCR20, FCR21, FCR22, FCR23,
    FCR24, FCR25, FCR26, FCR27, FCR28, FCR29, FCR30, Status,
};
// zig fmt: on

pub const Format = enum {
    S,
    D,
    W,
    L,

    pub fn Type(comptime self: @This()) type {
        return switch (comptime self) {
            .S => f32,
            .D => f64,
            .W => i32,
            .L => i64,
        };
    }
};

pub const RType = packed struct(u32) {
    funct: u6,
    fd: Register,
    fs: Register,
    ft: Register,
    fmt: u5,
    opcode: u6,
};

pub const IType = packed struct(u32) {
    imm: u16,
    ft: Register,
    rs: Core.Register,
    opcode: u6,
};

pub fn MType(comptime T: type) type {
    return packed struct(u32) {
        __: u11,
        fs: T,
        rt: Core.Register,
        rs: u5,
        opcode: u6,
    };
}

const Self = @This();

regs: [32]u64 = @splat(0),
csr: Csr = .{},

pub fn init() Self {
    return .{};
}

pub fn get(self: *Self, comptime fmt: Format, reg: Register) fmt.Type() {
    var index = @intFromEnum(reg);

    return switch (comptime fmt) {
        .S, .W => blk: {
            const result = if (self.fr() or (index & 1) == 0)
                self.regs[index]
            else
                self.regs[index & ~@as(u5, 1)] >> 32;

            break :blk @bitCast(@as(u32, @truncate(result)));
        },
        .D, .L => blk: {
            if (!self.fr()) {
                index &= ~@as(u5, 1);
            }

            break :blk @bitCast(self.regs[index]);
        },
    };
}

pub fn set(self: *Self, comptime fmt: Format, reg: Register, value: fmt.Type()) void {
    var index = @intFromEnum(reg);

    switch (comptime fmt) {
        .S, .W => {
            if (self.fr() or (index & 1) == 0) {
                self.regs[index] &= ~@as(u64, std.math.maxInt(u32));
                self.regs[index] |= @as(u64, @as(u32, @bitCast(value)));
            } else {
                index &= ~@as(u5, 1);
                self.regs[index] &= @as(u64, std.math.maxInt(u32));
                self.regs[index] |= @as(u64, @as(u32, @bitCast(value))) << 32;
            }

            fw.log.trace("  {t}: {d} ({X:08})", .{
                reg,
                @as(f32, @bitCast(value)),
                @as(u32, @bitCast(value)),
            });
        },
        .D, .L => {
            if (!self.fr()) {
                index &= ~@as(u5, 1);
            }

            self.regs[index] = @bitCast(value);

            fw.log.trace("  {t}: {d} ({X:08})", .{
                reg,
                @as(f64, @bitCast(value)),
                @as(u64, @bitCast(value)),
            });
        },
    }
}

fn fr(self: *const Self) bool {
    const core: *const Core = @alignCast(@fieldParentPtr("cp1", self));
    return core.cp0.fr();
}

pub fn cop1(word: u32) *const Core.Instruction {
    const rs: u5 = @truncate(word >> 21);

    return switch (rs) {
        0o10 => branch_table[@as(u5, @truncate(word >> 16))],
        0o20 => single_table[@as(u6, @truncate(word))],
        0o21 => double_table[@as(u6, @truncate(word))],
        0o24 => word_table[@as(u6, @truncate(word))],
        0o25 => long_table[@as(u6, @truncate(word))],
        else => main_table[rs],
    };
}

pub fn checkUsable(core: *Core) void {
    if (!core.cp0.cp1Usable()) {
        @branchHint(.unlikely);
        core.except(.{ .coprocessor_unusable = 1 });
        return;
    }
}

fn mfc1(core: *Core, word: u32) void {
    checkUsable(core);
    const args: MType(Register) = @bitCast(word);
    fw.log.trace("{X:08}: MFC1 {t}, {t}", .{ core.pc, args.rt, args.fs });
    core.set(args.rt, fw.num.signExtend(u64, core.cp1.get(.W, args.fs)));
}

fn dmfc1(core: *Core, word: u32) void {
    checkUsable(core);
    const args: MType(Register) = @bitCast(word);
    fw.log.trace("{X:08}: DMFC1 {t}, {t}", .{ core.pc, args.rt, args.fs });
    core.set(args.rt, @bitCast(core.cp1.get(.L, args.fs)));
}

fn mtc1(core: *Core, word: u32) void {
    checkUsable(core);
    const args: MType(Register) = @bitCast(word);
    fw.log.trace("{X:08}: MTC1 {t}, {t}", .{ core.pc, args.rt, args.fs });
    core.cp1.set(.W, args.fs, fw.num.truncate(i32, core.get(args.rt)));
}

fn dmtc1(core: *Core, word: u32) void {
    checkUsable(core);
    const args: MType(Register) = @bitCast(word);
    fw.log.trace("{X:08}: DMTC1 {t}, {t}", .{ core.pc, args.rt, args.fs });
    core.cp1.set(.L, args.fs, @bitCast(core.get(args.rt)));
}

fn cfc1(core: *Core, word: u32) void {
    checkUsable(core);

    const args: MType(ControlRegister) = @bitCast(word);

    fw.log.trace("{X:08}: CFC1 {t}, {t}", .{ core.pc, args.rt, args.fs });

    core.set(args.rt, fw.num.signExtend(u64, switch (args.fs) {
        .Revision => 0x0000_0a00,
        .Status => @as(u32, @bitCast(core.cp1.csr)),
        else => fw.log.unimplemented("Read from CPU CP1 {t}", .{args.fs}),
    }));
}

fn ctc1(core: *Core, word: u32) void {
    checkUsable(core);

    const args: MType(ControlRegister) = @bitCast(word);

    fw.log.trace("{X:08}: CTC1 {t}, {t}", .{ core.pc, args.rt, args.fs });

    const value: u32 = @truncate(core.get(args.rt));

    switch (args.fs) {
        .Revision => {}, // Not writable
        .Status => {
            fw.num.writeMasked(u32, @ptrCast(&core.cp1.csr), value, 0x0183_ffff);
            fw.log.trace("  CSR: {any}", .{core.cp1.csr});
        },
        else => fw.log.unimplemented("Read from CPU CP1 {t}", .{args.fs}),
    }
}

const RoundingMode = enum(u2) {
    round,
    trunc,
    ceil,
    floor,
};

const Csr = packed struct(u32) {
    rm: RoundingMode = .round,
    flags: u5 = 0,
    enables: u5 = 0,
    cause: u6 = 0,
    __0: u5 = 0,
    c: bool = false,
    fs: bool = false,
    __: u7 = 0,
};

pub const main_table: [32]*const Core.Instruction = blk: {
    var ops: [32]*const Core.Instruction = @splat(Core.reserved);
    ops[0o00] = mfc1;
    ops[0o01] = dmfc1;
    ops[0o02] = cfc1;
    ops[0o04] = mtc1;
    ops[0o05] = dmtc1;
    ops[0o06] = ctc1;
    break :blk ops;
};

pub const branch_table: [32]*const Core.Instruction = blk: {
    var ops: [32]*const Core.Instruction = @splat(Core.reserved);
    ops[0o00] = compare.branch(.BC1F, .{});
    ops[0o01] = compare.branch(.BC1T, .{});
    ops[0o02] = compare.branch(.BC1F, .{ .likely = true });
    ops[0o03] = compare.branch(.BC1T, .{ .likely = true });
    break :blk ops;
};

fn floatTable(comptime fmt: Format) [64]*const Core.Instruction {
    var ops: [64]*const Core.Instruction = @splat(Core.reserved);
    ops[0o00] = arithmetic.binary(.ADD, fmt);
    ops[0o01] = arithmetic.binary(.SUB, fmt);
    ops[0o02] = arithmetic.binary(.MUL, fmt);
    ops[0o03] = arithmetic.binary(.DIV, fmt);
    ops[0o04] = arithmetic.unary(.SQRT, fmt);
    ops[0o05] = arithmetic.unary(.ABS, fmt);
    ops[0o06] = arithmetic.unary(.MOV, fmt);
    ops[0o07] = arithmetic.unary(.NEG, fmt);
    ops[0o10] = convert.cvt(.ROUND, .L, fmt);
    ops[0o11] = convert.cvt(.TRUNC, .L, fmt);
    ops[0o12] = convert.cvt(.CEIL, .L, fmt);
    ops[0o13] = convert.cvt(.FLOOR, .L, fmt);
    ops[0o14] = convert.cvt(.ROUND, .W, fmt);
    ops[0o15] = convert.cvt(.TRUNC, .W, fmt);
    ops[0o16] = convert.cvt(.CEIL, .W, fmt);
    ops[0o17] = convert.cvt(.FLOOR, .W, fmt);
    ops[0o40] = convert.cvt(.CVT, .S, fmt);
    ops[0o41] = convert.cvt(.CVT, .D, fmt);
    ops[0o44] = convert.cvt(.CVT, .W, fmt);
    ops[0o45] = convert.cvt(.CVT, .L, fmt);
    ops[0o60] = compare.c(.F, fmt);
    ops[0o61] = compare.c(.UN, fmt);
    ops[0o62] = compare.c(.EQ, fmt);
    ops[0o63] = compare.c(.UEQ, fmt);
    ops[0o64] = compare.c(.OLT, fmt);
    ops[0o65] = compare.c(.ULT, fmt);
    ops[0o66] = compare.c(.OLE, fmt);
    ops[0o67] = compare.c(.ULE, fmt);
    ops[0o70] = compare.c(.SF, fmt);
    ops[0o71] = compare.c(.NGLE, fmt);
    ops[0o72] = compare.c(.SEQ, fmt);
    ops[0o73] = compare.c(.NGL, fmt);
    ops[0o74] = compare.c(.LT, fmt);
    ops[0o75] = compare.c(.NGE, fmt);
    ops[0o76] = compare.c(.LE, fmt);
    ops[0o77] = compare.c(.NGT, fmt);
    return ops;
}

pub const single_table = floatTable(.S);
pub const double_table = floatTable(.D);

fn intTable(comptime fmt: Format) [64]*const Core.Instruction {
    var ops: [64]*const Core.Instruction = @splat(Core.reserved);
    ops[0o40] = convert.cvt(.CVT, .S, fmt);
    ops[0o41] = convert.cvt(.CVT, .D, fmt);
    return ops;
}

pub const word_table = intTable(.W);
pub const long_table = intTable(.L);
