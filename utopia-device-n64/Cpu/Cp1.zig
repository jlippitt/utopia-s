const std = @import("std");
const fw = @import("framework");
const Core = @import("../Cpu.zig");
const arithmetic = @import("./Cp1/arithmetic.zig");
const convert = @import("./Cp1/convert.zig");

// zig fmt: off
const Register = enum(u5) {
    F0,  F1,  F2,  F3,  F4,  F5,  F6,  F7,
    F8,  F9,  F10, F11, F12, F13, F14, F15,
    F16, F17, F18, F19, F20, F21, F22, F23,
    F24, F25, F26, F27, F28, F29, F30, F31,
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

const IType = packed struct(u32) {
    imm: u16,
    ft: Register,
    rs: Core.Register,
    opcode: u6,
};

const Self = @This();

regs: [32]u64 = @splat(0),

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
        0o20 => floatOp(.S, core, word),
        0o21 => floatOp(.D, core, word),
        0o24 => intOp(.W, core, word),
        0o25 => intOp(.L, core, word),
        else => fw.log.todo("CPU COP1 rs: {o:02}", .{rs}),
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
        0o10 => convert.round(.ROUND, .L, fmt, core, word),
        0o11 => convert.round(.TRUNC, .L, fmt, core, word),
        0o12 => convert.round(.CEIL, .L, fmt, core, word),
        0o13 => convert.round(.FLOOR, .L, fmt, core, word),
        0o14 => convert.round(.ROUND, .W, fmt, core, word),
        0o15 => convert.round(.TRUNC, .W, fmt, core, word),
        0o16 => convert.round(.CEIL, .W, fmt, core, word),
        0o17 => convert.round(.FLOOR, .W, fmt, core, word),
        else => |funct| fw.log.todo("CPU COP1 float op: {o:02}", .{funct}),
    }
}

fn intOp(comptime fmt: Format, core: *Core, word: u32) void {
    _ = fmt;
    _ = core;

    switch (@as(u6, @truncate(word))) {
        else => |funct| fw.log.todo("CPU COP1 int op: {o:02}", .{funct}),
    }
}

pub const LoadOp = enum {
    LWC1,
    LDC1,

    fn alignMask(comptime op: @This()) u32 {
        return switch (comptime op) {
            .LWC1 => 3,
            .LDC1 => 7,
        };
    }
};

pub fn load(comptime op: LoadOp, comptime bus: Core.Bus, core: *Core, word: u32) void {
    const args: IType = @bitCast(word);
    const offset = fw.num.signExtend(u32, args.imm);

    fw.log.trace("{X:08}: {t} {t}, {d}({t})", .{
        core.pc,
        op,
        args.ft,
        @as(i32, @bitCast(offset)),
        args.rs,
    });

    const vaddr = @as(u32, @truncate(core.get(args.rs))) +% offset;
    const paddr = core.mapAddress(vaddr) orelse return;

    if ((paddr & op.alignMask()) != 0) {
        @branchHint(.cold);
        fw.log.todo("CPU alignment exceptions", .{});
    }

    switch (comptime op) {
        .LWC1 => core.cp1.set(.W, args.ft, @bitCast(core.readWord(bus, paddr))),
        .LDC1 => core.cp1.set(.L, args.ft, @bitCast(core.readDoubleWord(bus, paddr))),
    }
}

pub const StoreOp = enum {
    SWC1,
    SDC1,

    fn alignMask(comptime op: @This()) u32 {
        return switch (comptime op) {
            .SWC1 => 3,
            .SDC1 => 7,
        };
    }
};

pub fn store(comptime op: StoreOp, comptime bus: Core.Bus, core: *Core, word: u32) void {
    const args: IType = @bitCast(word);
    const offset = fw.num.signExtend(u32, args.imm);

    fw.log.trace("{X:08}: {t} {t}, {d}({t})", .{
        core.pc,
        op,
        args.ft,
        @as(i32, @bitCast(offset)),
        args.rs,
    });

    const vaddr = @as(u32, @truncate(core.get(args.rs))) +% offset;
    const paddr = core.mapAddress(vaddr) orelse return;

    if ((paddr & op.alignMask()) != 0) {
        @branchHint(.cold);
        fw.log.todo("CPU alignment exceptions", .{});
    }

    switch (comptime op) {
        .SWC1 => core.writeWord(
            bus,
            paddr,
            @bitCast(core.cp1.get(.W, args.ft)),
            std.math.maxInt(u32),
        ),
        .SDC1 => core.writeDoubleWord(
            bus,
            paddr,
            @bitCast(core.cp1.get(.L, args.ft)),
            std.math.maxInt(u64),
        ),
    }
}
