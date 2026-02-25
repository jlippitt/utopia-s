const fw = @import("framework");
const Core = @import("../Cpu.zig");

pub const UnaryBranchOp = enum {
    BLTZ,
    BLEZ,
    BGEZ,
    BGTZ,
};

pub const BinaryBranchOp = enum {
    BEQ,
    BNE,
};

pub fn branchUnary(
    comptime op: UnaryBranchOp,
    comptime params: Core.BranchParams,
    core: *Core,
    word: u32,
) void {
    const args: Core.IType = @bitCast(word);
    const offset = fw.num.signExtend(u32, args.imm) << 2;

    fw.log.trace("{X:08}: {t}{s}{s} {t}, {d}", .{
        core.pc,
        op,
        if (params.link) "AL" else "",
        if (params.likely) "L" else "",
        args.rs,
        @as(i32, @bitCast(offset)),
    });

    const value: i64 = @bitCast(core.get(args.rs));

    const taken = switch (comptime op) {
        .BLTZ => value < 0,
        .BLEZ => value <= 0,
        .BGEZ => value >= 0,
        .BGTZ => value > 0,
    };

    core.branch(params, offset, taken);
}

pub fn branchBinary(
    comptime op: BinaryBranchOp,
    comptime params: Core.BranchParams,
    core: *Core,
    word: u32,
) void {
    const args: Core.IType = @bitCast(word);
    const offset = fw.num.signExtend(u32, args.imm) << 2;

    fw.log.trace("{X:08}: {t}{s}{s} {t}, {t}, {d}", .{
        core.pc,
        op,
        if (params.link) "AL" else "",
        if (params.likely) "L" else "",
        args.rs,
        args.rt,
        @as(i32, @bitCast(offset)),
    });

    const lhs = core.get(args.rs);
    const rhs = core.get(args.rt);

    const taken = switch (comptime op) {
        .BEQ => lhs == rhs,
        .BNE => lhs != rhs,
    };

    core.branch(params, offset, taken);
}
