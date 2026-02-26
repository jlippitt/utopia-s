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
        _: u11,
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

            fw.log.trace("  {t}.{t}: {d} ({X:08})", .{
                reg,
                fmt,
                @as(f32, @floatFromInt(@as(u32, @truncate(self.regs[index])))),
                @as(i32, @bitCast(@as(u32, @truncate(self.regs[index])))),
            });
        },
        .D, .L => {
            if (!self.fr()) {
                index &= ~@as(u5, 1);
            }

            self.regs[index] = @bitCast(value);

            fw.log.trace("  {t}.{t}: {d} ({X:08})", .{
                reg,
                fmt,
                @as(f64, @floatFromInt(self.regs[index])),
                @as(i64, @bitCast(self.regs[index])),
            });
        },
    }
}

fn fr(self: *const Self) bool {
    const core: *const Core = @alignCast(@fieldParentPtr("cp1", self));
    return core.cp0.fr();
}

pub fn cop1(core: *Core, word: u32) void {
    const rs: u5 = @truncate(word >> 21);

    switch (rs) {
        0o00 => mfc1(core, word),
        0o01 => dmfc1(core, word),
        0o02 => cfc1(core, word),
        0o04 => mtc1(core, word),
        0o05 => dmtc1(core, word),
        0o06 => ctc1(core, word),
        0o10 => branchOp(core, word),
        0o20 => floatOp(.S, core, word),
        0o21 => floatOp(.D, core, word),
        0o24 => intOp(.W, core, word),
        0o25 => intOp(.L, core, word),
        else => fw.log.todo("CPU COP1 rs: {o:02}", .{rs}),
    }
}

fn branchOp(core: *Core, word: u32) void {
    switch (@as(u5, @truncate(word >> 16))) {
        0o00 => compare.branch(.BC1F, .{}, core, word),
        0o01 => compare.branch(.BC1T, .{}, core, word),
        0o02 => compare.branch(.BC1F, .{ .likely = true }, core, word),
        0o03 => compare.branch(.BC1T, .{ .likely = true }, core, word),
        else => |rt| fw.log.todo("CPU COP1 branch op: {o:02}", .{rt}),
    }
}

fn floatOp(comptime fmt: Format, core: *Core, word: u32) void {
    switch (@as(u6, @truncate(word))) {
        0o00 => arithmetic.binary(.ADD, fmt, core, word),
        0o01 => arithmetic.binary(.SUB, fmt, core, word),
        0o02 => arithmetic.binary(.MUL, fmt, core, word),
        0o03 => arithmetic.binary(.DIV, fmt, core, word),
        0o04 => arithmetic.unary(.SQRT, fmt, core, word),
        0o05 => arithmetic.unary(.ABS, fmt, core, word),
        0o06 => arithmetic.unary(.MOV, fmt, core, word),
        0o07 => arithmetic.unary(.NEG, fmt, core, word),
        0o10 => convert.cvt(.ROUND, .L, fmt, core, word),
        0o11 => convert.cvt(.TRUNC, .L, fmt, core, word),
        0o12 => convert.cvt(.CEIL, .L, fmt, core, word),
        0o13 => convert.cvt(.FLOOR, .L, fmt, core, word),
        0o14 => convert.cvt(.ROUND, .W, fmt, core, word),
        0o15 => convert.cvt(.TRUNC, .W, fmt, core, word),
        0o16 => convert.cvt(.CEIL, .W, fmt, core, word),
        0o17 => convert.cvt(.FLOOR, .W, fmt, core, word),
        0o40 => convert.cvt(.CVT, .S, fmt, core, word),
        0o41 => convert.cvt(.CVT, .D, fmt, core, word),
        0o44 => convert.cvt(.CVT, .W, fmt, core, word),
        0o45 => convert.cvt(.CVT, .L, fmt, core, word),
        0o60 => compare.c(.F, fmt, core, word),
        0o61 => compare.c(.UN, fmt, core, word),
        0o62 => compare.c(.EQ, fmt, core, word),
        0o63 => compare.c(.UEQ, fmt, core, word),
        0o64 => compare.c(.OLT, fmt, core, word),
        0o65 => compare.c(.ULT, fmt, core, word),
        0o66 => compare.c(.OLE, fmt, core, word),
        0o67 => compare.c(.ULE, fmt, core, word),
        0o70 => compare.c(.SF, fmt, core, word),
        0o71 => compare.c(.NGLE, fmt, core, word),
        0o72 => compare.c(.SEQ, fmt, core, word),
        0o73 => compare.c(.NGL, fmt, core, word),
        0o74 => compare.c(.LT, fmt, core, word),
        0o75 => compare.c(.NGE, fmt, core, word),
        0o76 => compare.c(.LE, fmt, core, word),
        0o77 => compare.c(.NGT, fmt, core, word),
        else => |funct| fw.log.todo("CPU COP1 float op: {o:02}", .{funct}),
    }
}

fn intOp(comptime fmt: Format, core: *Core, word: u32) void {
    switch (@as(u6, @truncate(word))) {
        0o40 => convert.cvt(.CVT, .S, fmt, core, word),
        0o41 => convert.cvt(.CVT, .D, fmt, core, word),
        else => |funct| fw.log.todo("CPU COP1 int op: {o:02}", .{funct}),
    }
}

fn mfc1(core: *Core, word: u32) void {
    const args: MType(Register) = @bitCast(word);
    fw.log.trace("{X:08}: MFC1 {t}, {t}", .{ core.pc, args.rt, args.fs });
    core.set(args.rt, fw.num.signExtend(u64, core.cp1.get(.W, args.fs)));
}

fn dmfc1(core: *Core, word: u32) void {
    const args: MType(Register) = @bitCast(word);
    fw.log.trace("{X:08}: DMFC1 {t}, {t}", .{ core.pc, args.rt, args.fs });
    core.set(args.rt, @bitCast(core.cp1.get(.L, args.fs)));
}

fn mtc1(core: *Core, word: u32) void {
    const args: MType(Register) = @bitCast(word);
    fw.log.trace("{X:08}: MTC1 {t}, {t}", .{ core.pc, args.rt, args.fs });
    core.cp1.set(.W, args.fs, fw.num.truncate(i32, core.get(args.rt)));
}

fn dmtc1(core: *Core, word: u32) void {
    const args: MType(Register) = @bitCast(word);
    fw.log.trace("{X:08}: DMTC1 {t}, {t}", .{ core.pc, args.rt, args.fs });
    core.cp1.set(.L, args.fs, @bitCast(core.get(args.rt)));
}

fn cfc1(core: *Core, word: u32) void {
    const args: MType(ControlRegister) = @bitCast(word);

    fw.log.trace("{X:08}: CFC1 {t}, {t}", .{ core.pc, args.rt, args.fs });

    core.set(args.rt, fw.num.signExtend(u64, switch (args.fs) {
        .Revision => 0x0000_0a00,
        .Status => @as(u32, @bitCast(core.cp1.csr)),
        else => fw.log.unimplemented("Read from CPU CP1 {t}", .{args.fs}),
    }));
}

fn ctc1(core: *Core, word: u32) void {
    const args: MType(ControlRegister) = @bitCast(word);

    fw.log.trace("{X:08}: CTC1 {t}, {t}", .{ core.pc, args.rt, args.fs });

    const value: u32 = @truncate(core.get(args.rt));

    switch (args.fs) {
        .Revision => {}, // Not writable
        .Status => {
            core.cp1.csr = @bitCast(value);
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
