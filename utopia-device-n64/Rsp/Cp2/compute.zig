const std = @import("std");
const fw = @import("framework");
const Core = @import("../Core.zig");
const Cp2 = @import("../Cp2.zig");

const Args = packed struct(u32) {
    funct: u6,
    vd: Cp2.Register,
    vs: Cp2.Register,
    vt: Cp2.Register,
    el: u4,
    __: u1,
    opcode: u6,
};

pub const ComputeOp = enum {
    VMULF,
    VMULU,
    VMUDL,
    VMUDM,
    VMUDN,
    VMUDH,
    VMACF,
    VMACU,
    VMADL,
    VMADM,
    VMADN,
    VMADH,
};

pub fn compute(comptime op: ComputeOp, core: *Core, word: u32) void {
    const args: Args = @bitCast(word);

    fw.log.trace("{X:03}: {t} {t}, {t}, {t}[E:{d}]", .{
        core.pc,
        args.vd,
        args.vs,
        args.vt,
        args.el,
    });

    const lhs = core.cp2.get(args.vs);
    const rhs = core.cp2.broadcast(args.vt, args.el);

    core.cp2.set(args.vd, switch (comptime op) {
        .VMULF => blk: {
            const result = fw.num.signExtend(@Vector(8, i32), lhs) *
                fw.num.signExtend(@Vector(8, i32), rhs);

            core.cp2.acc = @splat(0x8000);
            core.cp2.acc +%= fw.num.signExtend(@Vector(8, u48), result) << @splat(1);

            break :blk @truncate(clampSigned(core.cp2.acc) >> @splat(16));
        },
        .VMULU => blk: {
            const result = fw.num.signExtend(@Vector(8, i32), lhs) *
                fw.num.signExtend(@Vector(8, i32), rhs);

            core.cp2.acc = @splat(0x8000);
            core.cp2.acc +%= fw.num.signExtend(@Vector(8, u48), result) << @splat(1);

            break :blk @truncate(clampUnsigned(core.cp2.acc) >> @splat(16));
        },
        .VMUDL => blk: {
            const result = @as(@Vector(8, u32), lhs) *
                @as(@Vector(8, u32), rhs);

            core.cp2.acc = result >> @splat(16);

            break :blk @truncate(core.cp2.acc);
        },
        .VMUDM => blk: {
            const result = fw.num.signExtend(@Vector(8, i32), lhs) *
                fw.num.zeroExtend(@Vector(8, i32), rhs);

            core.cp2.acc = fw.num.signExtend(@Vector(8, u48), result);

            break :blk @truncate(core.cp2.acc >> @splat(16));
        },
        .VMUDN => blk: {
            const result = fw.num.zeroExtend(@Vector(8, i32), lhs) *
                fw.num.signExtend(@Vector(8, i32), rhs);

            core.cp2.acc = fw.num.signExtend(@Vector(8, u48), result);

            break :blk @truncate(core.cp2.acc);
        },
        .VMUDH => blk: {
            const result = fw.num.signExtend(@Vector(8, i32), lhs) *
                fw.num.signExtend(@Vector(8, i32), rhs);

            core.cp2.acc = fw.num.signExtend(@Vector(8, u48), result) << @splat(16);

            break :blk @truncate(clampSigned(core.cp2.acc) >> @splat(16));
        },
        .VMACF => blk: {
            const result = fw.num.signExtend(@Vector(8, i32), lhs) *
                fw.num.signExtend(@Vector(8, i32), rhs);

            core.cp2.acc +%= fw.num.signExtend(@Vector(8, u48), result) << @splat(1);

            break :blk @truncate(clampSigned(core.cp2.acc) >> @splat(16));
        },
        .VMACU => blk: {
            const result = fw.num.signExtend(@Vector(8, i32), lhs) *
                fw.num.signExtend(@Vector(8, i32), rhs);

            core.cp2.acc +%= fw.num.signExtend(@Vector(8, u48), result) << @splat(1);

            break :blk @truncate(clampUnsigned(core.cp2.acc) >> @splat(16));
        },
        .VMADL => blk: {
            const result = @as(@Vector(8, u32), lhs) *
                @as(@Vector(8, u32), rhs);

            core.cp2.acc +%= result >> @splat(16);

            break :blk @truncate(clampSigned(core.cp2.acc));
        },
        .VMADM => blk: {
            const result = fw.num.signExtend(@Vector(8, i32), lhs) *
                fw.num.zeroExtend(@Vector(8, i32), rhs);

            core.cp2.acc +%= fw.num.signExtend(@Vector(8, u48), result);

            break :blk @truncate(clampSigned(core.cp2.acc) >> @splat(16));
        },
        .VMADN => blk: {
            const result = fw.num.zeroExtend(@Vector(8, i32), lhs) *
                fw.num.signExtend(@Vector(8, i32), rhs);

            core.cp2.acc +%= fw.num.signExtend(@Vector(8, u48), result);

            break :blk @truncate(clampSigned(core.cp2.acc));
        },
        .VMADH => blk: {
            const result = fw.num.signExtend(@Vector(8, i32), lhs) *
                fw.num.signExtend(@Vector(8, i32), rhs);

            core.cp2.acc +%= fw.num.signExtend(@Vector(8, u48), result) << @splat(16);

            break :blk @truncate(clampSigned(core.cp2.acc) >> @splat(16));
        },
    });
}

pub fn vsar(core: *Core, word: u32) void {
    const args: Args = @bitCast(word);

    fw.log.trace("{X:03}: VSAR {t}[E:{d}]", .{ core.pc, args.vd, args.el });

    core.cp2.set(args.vd, switch (args.el) {
        8 => @truncate(core.cp2.acc >> @splat(32)),
        9 => @truncate(core.cp2.acc >> @splat(16)),
        10 => @truncate(core.cp2.acc),
        else => @splat(0),
    });
}

fn clampSigned(acc: @Vector(8, u48)) @Vector(8, u48) {
    return @bitCast(std.math.clamp(
        @as(@Vector(8, i48), @bitCast(acc)),
        @as(@Vector(8, i48), @splat(std.math.minInt(i32))),
        @as(@Vector(8, i48), @splat(std.math.maxInt(i32))),
    ));
}

fn clampUnsigned(acc: @Vector(8, u48)) @Vector(8, u48) {
    const clipped = @select(
        u48,
        acc < @as(@Vector(8, u48), @splat(0x8000_0000)),
        acc,
        @as(@Vector(8, u48), @splat(std.math.maxInt(u48))),
    );

    return @select(
        u48,
        acc < @as(@Vector(8, u48), @splat(0x8000_0000_0000)),
        clipped,
        @as(@Vector(8, u48), @splat(0)),
    );
}
