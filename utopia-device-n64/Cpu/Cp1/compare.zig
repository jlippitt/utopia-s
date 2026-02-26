const std = @import("std");
const fw = @import("framework");
const Core = @import("../../Cpu.zig");
const Cp1 = @import("../Cp1.zig");

pub const CompareOp = enum {
    F,
    UN,
    EQ,
    UEQ,
    OLT,
    ULT,
    OLE,
    ULE,
    SF,
    NGLE,
    SEQ,
    NGL,
    LT,
    NGE,
    LE,
    NGT,
};

pub fn c(comptime op: CompareOp, comptime fmt: Cp1.Format, core: *Core, word: u32) void {
    const args: Cp1.RType = @bitCast(word);

    fw.log.trace("{X:08}: C.{t}.{t} {t}, {t}", .{
        core.pc,
        op,
        fmt,
        args.fs,
        args.ft,
    });

    const lhs = core.cp1.get(fmt, args.fs);
    const rhs = core.cp1.get(fmt, args.ft);

    const unordered = std.math.isNan(lhs) or std.math.isNan(rhs);

    core.cp1.csr.c = switch (comptime op) {
        .F, .SF => false,
        .UN, .NGLE => unordered,
        .EQ, .SEQ => lhs == rhs,
        .UEQ, .NGL => lhs == rhs or unordered,
        .OLT, .LT => lhs < rhs,
        .ULT, .NGE => lhs < rhs or unordered,
        .OLE, .LE => lhs <= rhs,
        .ULE, .NGT => lhs <= rhs or unordered,
    };

    fw.log.trace("  CSR.C: {}", .{core.cp1.csr.c});

    if ((comptime @intFromEnum(op) >= @intFromEnum(CompareOp.SF)) and unordered) {
        fw.log.todo("CPU floating point exceptions", .{});
    }
}

pub const BranchOp = enum {
    BC1F,
    BC1T,
};

pub fn branch(
    comptime op: BranchOp,
    comptime params: Core.BranchParams,
    core: *Core,
    word: u32,
) void {
    const args: Cp1.IType = @bitCast(word);
    const offset = fw.num.signExtend(u32, args.imm) << 2;

    fw.log.trace("{X:08}: {t}{s}{s} {d}", .{
        core.pc,
        op,
        if (params.link) "AL" else "",
        if (params.likely) "L" else "",
        @as(i32, @bitCast(offset)),
    });

    const taken = switch (comptime op) {
        .BC1F => !core.cp1.csr.c,
        .BC1T => core.cp1.csr.c,
    };

    core.branch(params, offset, taken);
}
