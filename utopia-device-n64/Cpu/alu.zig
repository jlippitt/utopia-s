const std = @import("std");
const fw = @import("framework");
const Core = @import("../Cpu.zig");

pub fn lui(core: *Core, word: u32) void {
    const args: Core.IType = @bitCast(word);
    fw.log.trace("{X:08}: LUI {t}, 0x{X:04}", .{ core.pc, args.rt, args.imm });
    core.set(args.rt, fw.num.signExtend(u64, @as(u32, args.imm) << 16));
}

pub const LogicOp = enum {
    AND,
    OR,
    XOR,
    NOR,

    fn apply(comptime op: @This(), lhs: u64, rhs: u64) u64 {
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
    fw.log.trace("{X:08}: {t}I {t}, {t}, 0x{X:04}", .{ core.pc, op, args.rt, args.rs, args.imm });
    core.set(args.rt, op.apply(core.get(args.rs), args.imm));
}

pub fn rTypeLogic(comptime op: LogicOp, core: *Core, word: u32) void {
    const args: Core.RType = @bitCast(word);
    fw.log.trace("{X:08}: {t} {t}, {t}, {t}", .{ core.pc, op, args.rd, args.rs, args.rt });
    core.set(args.rd, op.apply(core.get(args.rs), core.get(args.rt)));
}

pub const ArithmeticOp = enum {
    ADD,
    DADD,
    SUB,
    DSUB,
    SLT,

    fn apply(
        comptime op: @This(),
        comptime signedness: std.builtin.Signedness,
        lhs: u64,
        rhs: u64,
    ) !u64 {
        return switch (comptime signedness) {
            .signed => switch (comptime op) {
                .ADD => fw.num.signExtend(
                    u64,
                    try std.math.add(i32, fw.num.truncate(i32, lhs), fw.num.truncate(i32, rhs)),
                ),
                .DADD => @bitCast(try std.math.sub(i64, @bitCast(lhs), @bitCast(rhs))),
                .SUB => fw.num.signExtend(
                    u64,
                    try std.math.add(i32, fw.num.truncate(i32, lhs), fw.num.truncate(i32, rhs)),
                ),
                .DSUB => @bitCast(try std.math.sub(i64, @bitCast(lhs), @bitCast(rhs))),
                .SLT => @intFromBool(@as(i64, @bitCast(lhs)) < @as(i64, @bitCast(rhs))),
            },
            .unsigned => switch (comptime op) {
                .ADD => fw.num.signExtend(
                    u64,
                    @as(u32, @truncate(lhs)) +% @as(u32, @truncate(rhs)),
                ),
                .DADD => lhs +% rhs,
                .SUB => fw.num.signExtend(
                    u64,
                    @as(u32, @truncate(lhs)) -% @as(u32, @truncate(rhs)),
                ),
                .DSUB => lhs -% rhs,
                .SLT => @intFromBool(lhs < rhs),
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
    const offset = fw.num.signExtend(u64, args.imm);

    fw.log.trace("{X:08}: {t}I{s} {t}, {t}, {d}", .{
        core.pc,
        op,
        if (signedness == .unsigned) "U" else "",
        args.rt,
        args.rs,
        @as(i64, @bitCast(offset)),
    });

    core.set(args.rt, op.apply(signedness, core.get(args.rs), offset) catch {
        @branchHint(.cold);
        fw.log.todo("CPU overflow exceptions", .{});
        return;
    });
}

pub fn rTypeArithmetic(
    comptime op: ArithmeticOp,
    comptime signedness: std.builtin.Signedness,
    core: *Core,
    word: u32,
) void {
    const args: Core.RType = @bitCast(word);

    fw.log.trace("{X:08}: {t}{s} {t}, {t}, {t}", .{
        core.pc,
        op,
        if (signedness == .unsigned) "U" else "",
        args.rd,
        args.rs,
        args.rt,
    });

    core.set(args.rd, op.apply(signedness, core.get(args.rs), core.get(args.rt)) catch {
        @branchHint(.cold);
        fw.log.todo("CPU overflow exceptions", .{});
        return;
    });
}
