const std = @import("std");
const fw = @import("framework");
const Core = @import("./Core.zig");

pub fn lui(core: *Core, word: u32) void {
    const args: Core.IType = @bitCast(word);
    fw.log.trace("{X:03}: LUI {t}, 0x{X:04}", .{ core.pc, args.rt, args.imm });
    core.set(args.rt, @as(u32, args.imm) << 16);
}

pub const LogicOp = enum {
    AND,
    OR,
    XOR,
    NOR,

    fn apply(comptime op: @This(), lhs: u32, rhs: u32) u32 {
        return switch (comptime op) {
            .AND => lhs & rhs,
            .OR => lhs | rhs,
            .XOR => lhs ^ rhs,
            .NOR => ~(lhs | rhs),
        };
    }
};

pub fn iTypeLogic(comptime op: LogicOp, core: *Core, word: u32) void {
    const args: Core.IType = @bitCast(word);
    fw.log.trace("{X:03}: {t}I {t}, {t}, 0x{X:04}", .{ core.pc, op, args.rt, args.rs, args.imm });
    core.set(args.rt, op.apply(core.get(args.rs), args.imm));
}

pub fn rTypeLogic(comptime op: LogicOp, core: *Core, word: u32) void {
    const args: Core.RType = @bitCast(word);
    fw.log.trace("{X:03}: {t} {t}, {t}, {t}", .{ core.pc, op, args.rd, args.rs, args.rt });
    core.set(args.rd, op.apply(core.get(args.rs), core.get(args.rt)));
}

pub const ArithmeticOp = enum {
    ADD,
    SUB,
    SLT,

    fn apply(
        comptime op: @This(),
        comptime signedness: std.builtin.Signedness,
        lhs: u32,
        rhs: u32,
    ) u32 {
        return switch (comptime op) {
            .ADD => lhs +% rhs,
            .SUB => lhs -% rhs,
            .SLT => switch (comptime signedness) {
                .signed => @intFromBool(@as(i32, @bitCast(lhs)) < @as(i32, @bitCast(rhs))),
                .unsigned => @intFromBool(lhs < rhs),
            },
        };
    }
};

pub fn iTypeArithmetic(
    comptime op: ArithmeticOp,
    comptime signedness: std.builtin.Signedness,
    core: *Core,
    word: u32,
) void {
    const args: Core.IType = @bitCast(word);
    const offset = fw.num.signExtend(u32, args.imm);

    fw.log.trace("{X:03}: {t}I{s} {t}, {t}, {d}", .{
        core.pc,
        op,
        if (signedness == .unsigned) "U" else "",
        args.rt,
        args.rs,
        @as(i32, @bitCast(offset)),
    });

    core.set(args.rt, op.apply(signedness, core.get(args.rs), offset));
}

pub fn rTypeArithmetic(
    comptime op: ArithmeticOp,
    comptime signedness: std.builtin.Signedness,
    core: *Core,
    word: u32,
) void {
    const args: Core.RType = @bitCast(word);

    fw.log.trace("{X:03}: {t}{s} {t}, {t}, {t}", .{
        core.pc,
        op,
        if (signedness == .unsigned) "U" else "",
        args.rd,
        args.rs,
        args.rt,
    });

    core.set(args.rd, op.apply(signedness, core.get(args.rs), core.get(args.rt)));
}
