const std = @import("std");
const fw = @import("framework");
const Core = @import("./Core.zig");

const JumpParams = struct {
    link: bool = false,
};

pub fn j(comptime params: JumpParams, core: *Core, word: u32) void {
    const target: u12 = @truncate(word << 2);

    fw.log.trace("{X:03}: J{s} 0x{X:03}", .{
        core.pc,
        if (params.link) "AL" else "",
        target,
    });

    if (comptime params.link) {
        core.link(.RA);
    }

    core.jump(target);
}

pub fn jr(core: *Core, word: u32) void {
    const args: Core.RType = @bitCast(word);
    fw.log.trace("{X:03}: JR {t}", .{ core.pc, args.rs });
    core.jump(@truncate(core.get(args.rs) & 0xffc));
}

pub fn jalr(core: *Core, word: u32) void {
    const args: Core.RType = @bitCast(word);
    fw.log.trace("{X:03}: JALR {t}, {t}", .{ core.pc, args.rd, args.rs });
    const target: u12 = @truncate(core.get(args.rs) & 0xffc);
    core.link(args.rd);
    core.jump(target);
}

pub const UnaryBranchOp = enum {
    BLTZ,
    BLEZ,
    BGEZ,
    BGTZ,
};

pub fn branchUnary(
    comptime op: UnaryBranchOp,
    comptime params: Core.BranchParams,
    core: *Core,
    word: u32,
) void {
    const args: Core.IType = @bitCast(word);
    const offset: u12 = @truncate(args.imm << 2);

    fw.log.trace("{X:03}: {t}{s} {t}, {d}", .{
        core.pc,
        op,
        if (params.link) "AL" else "",
        args.rs,
        @as(i12, @bitCast(offset)),
    });

    const value: i32 = @bitCast(core.get(args.rs));

    const taken = switch (comptime op) {
        .BLTZ => value < 0,
        .BLEZ => value <= 0,
        .BGEZ => value >= 0,
        .BGTZ => value > 0,
    };

    core.branch(params, offset, taken);
}

pub const BinaryBranchOp = enum {
    BEQ,
    BNE,
};

pub fn branchBinary(
    comptime op: BinaryBranchOp,
    comptime params: Core.BranchParams,
    core: *Core,
    word: u32,
) void {
    const args: Core.IType = @bitCast(word);
    const offset: u12 = @truncate(args.imm << 2);

    fw.log.trace("{X:03}: {t}{s} {t}, {t}, {d}", .{
        core.pc,
        op,
        if (params.link) "AL" else "",
        args.rs,
        args.rt,
        @as(i12, @bitCast(offset)),
    });

    const lhs = core.get(args.rs);
    const rhs = core.get(args.rt);

    const taken = switch (comptime op) {
        .BEQ => lhs == rhs,
        .BNE => lhs != rhs,
    };

    core.branch(params, offset, taken);
}

pub fn break_(core: *Core, word: u32) void {
    _ = word;
    fw.log.trace("{X:03}: BREAK", .{core.pc});
    core.getRsp().break_();
}
