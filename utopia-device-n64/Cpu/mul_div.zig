const std = @import("std");
const fw = @import("framework");
const Core = @import("../Cpu.zig");

pub const MulDivOp = enum {
    MULT,
    MULTU,
    DMULT,
    DMULTU,
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
