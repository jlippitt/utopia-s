const std = @import("std");
const fw = @import("framework");
const Core = @import("../Cpu.zig");

pub const MulDivOp = enum {
    MULT,
    MULTU,
    DMULT,
    DMULTU,
    DIV,
    DIVU,
    DDIV,
    DDIVU,
};

pub fn mulDiv(comptime op: MulDivOp, core: *Core, word: u32) void {
    const args: Core.RType = @bitCast(word);

    fw.log.trace("{X:08}: {t} {t}, {t}", .{ core.pc, op, args.rs, args.rt });

    const lhs = core.get(args.rs);
    const rhs = core.get(args.rt);

    switch (comptime op) {
        .MULT => {
            const result: u64 = @bitCast(
                std.math.mulWide(
                    i32,
                    fw.num.truncate(i32, lhs),
                    fw.num.truncate(i32, rhs),
                ),
            );

            core.lo = fw.num.signExtend(u64, @as(u32, @truncate(result)));
            core.hi = fw.num.signExtend(u64, @as(u32, @truncate(result >> 32)));
        },
        .MULTU => {
            const result: u64 = std.math.mulWide(u32, @truncate(lhs), @truncate(rhs));
            core.lo = fw.num.signExtend(u64, @as(u32, @truncate(result)));
            core.hi = fw.num.signExtend(u64, @as(u32, @truncate(result >> 32)));
        },
        .DMULT => {
            const result: u128 = @bitCast(
                std.math.mulWide(
                    i64,
                    @bitCast(lhs),
                    @bitCast(rhs),
                ),
            );

            core.lo = @truncate(result);
            core.hi = @truncate(result >> 64);
        },
        .DMULTU => {
            const result: u128 = std.math.mulWide(u64, lhs, rhs);
            core.lo = @truncate(result);
            core.hi = @truncate(result >> 64);
        },
        .DIV => {
            const lhs_i32 = fw.num.truncate(i32, lhs);
            const rhs_i32 = fw.num.truncate(i32, rhs);

            if (rhs_i32 == 0) {
                @branchHint(.unlikely);
                core.lo = if (lhs_i32 < 0) 1 else std.math.maxInt(u64);
                core.hi = fw.num.signExtend(u64, lhs_i32);
            } else if (lhs_i32 == std.math.minInt(i32) and rhs_i32 == -1) {
                @branchHint(.unlikely);
                core.lo = fw.num.signExtend(u64, @as(i32, std.math.minInt(i32)));
                core.hi = 0;
            } else {
                core.lo = fw.num.signExtend(u64, @divTrunc(lhs_i32, rhs_i32));
                core.hi = fw.num.signExtend(u64, @rem(lhs_i32, rhs_i32));
            }
        },
        .DIVU => {
            const lhs_u32: u32 = @truncate(lhs);
            const rhs_u32: u32 = @truncate(rhs);

            if (rhs_u32 == 0) {
                @branchHint(.unlikely);
                core.lo = std.math.maxInt(u64);
                core.hi = fw.num.signExtend(u64, lhs_u32);
            } else {
                core.lo = fw.num.signExtend(u64, lhs_u32 / rhs_u32);
                core.hi = fw.num.signExtend(u64, lhs_u32 % rhs_u32);
            }
        },
        .DDIV => {
            const lhs_i64: i64 = @bitCast(lhs);
            const rhs_i64: i64 = @bitCast(rhs);

            if (rhs_i64 == 0) {
                @branchHint(.unlikely);
                core.lo = if (lhs_i64 < 0) 1 else std.math.maxInt(u64);
                core.hi = @bitCast(lhs_i64);
            } else if (lhs_i64 == std.math.minInt(i64) and rhs_i64 == -1) {
                @branchHint(.unlikely);
                core.lo = @bitCast(@as(i64, std.math.minInt(i64)));
                core.hi = 0;
            } else {
                core.lo = @bitCast(@divTrunc(lhs_i64, rhs_i64));
                core.hi = @bitCast(@rem(lhs_i64, rhs_i64));
            }
        },
        .DDIVU => {
            if (rhs == 0) {
                @branchHint(.unlikely);
                core.lo = std.math.maxInt(u64);
                core.hi = lhs;
            } else {
                core.lo = lhs / rhs;
                core.hi = lhs % rhs;
            }
        },
    }

    fw.log.trace("  LO: {X:016}", .{core.lo});
    fw.log.trace("  HI: {X:016}", .{core.hi});
}

pub fn mflo(core: *Core, word: u32) void {
    const args: Core.RType = @bitCast(word);
    fw.log.trace("{X:08}: MFLO {t}", .{ core.pc, args.rd });
    core.set(args.rd, core.lo);
}

pub fn mfhi(core: *Core, word: u32) void {
    const args: Core.RType = @bitCast(word);
    fw.log.trace("{X:08}: MFHI {t}", .{ core.pc, args.rd });
    core.set(args.rd, core.hi);
}

pub fn mtlo(core: *Core, word: u32) void {
    const args: Core.RType = @bitCast(word);
    fw.log.trace("{X:08}: MTLO {t}", .{ core.pc, args.rs });
    core.lo = core.get(args.rs);
    fw.log.trace("  LO: {X:016}", .{core.lo});
}

pub fn mthi(core: *Core, word: u32) void {
    const args: Core.RType = @bitCast(word);
    fw.log.trace("{X:08}: MTHI {t}", .{ core.pc, args.rs });
    core.hi = core.get(args.rs);
    fw.log.trace("  HI: {X:016}", .{core.hi});
}
