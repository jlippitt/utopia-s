const fw = @import("framework");
const Core = @import("../Cpu.zig");

const JumpParams = struct {
    link: bool = false,
};

pub fn j(comptime params: JumpParams, core: *Core, word: u32) void {
    const target = (core.pc & 0xf000_0000) | ((@as(u32, word) << 2) & 0x0fff_fffc);

    fw.log.trace("{X:08}: J{s} 0x{X:08}", .{
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

    fw.log.trace("{X:08}: JR {t}", .{ core.pc, args.rs });

    const target: u32 = @truncate(core.get(args.rs));

    if ((target & 3) != 0) {
        @branchHint(.cold);
        fw.log.todo("CPU alignment exceptions", .{});
    }

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
