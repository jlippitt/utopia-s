const std = @import("std");
const fw = @import("framework");
const Core = @import("../Core.zig");
const Cp2 = @import("../Cp2.zig");

const zero: @Vector(8, u16) = @splat(0);
const i16_max: @Vector(8, u16) = @splat(0x7fff);
const i16_min: @Vector(8, u16) = @splat(0x8000);
const u16_max: @Vector(8, u16) = @splat(0xffff);
const v_false: @Vector(8, bool) = @splat(false);
const v_true: @Vector(8, bool) = @splat(true);

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
    VADD,
    VSUB,
    VABS,
    VADDC,
    VSUBC,
    VAND,
    VNAND,
    VOR,
    VNOR,
    VXOR,
    VNXOR,
    VEQ,
    VNE,
    VGE,
    VLT,
    VCL,
    VCH,
    VCR,
    VMRG,
};

pub fn compute(comptime op: ComputeOp) Core.Instruction {
    return struct {
        fn instr(core: *Core, word: u32) void {
            const args: Args = @bitCast(word);

            fw.log.trace("{X:03}: {t} {t}, {t}, {t}[E:{d}]", .{
                core.pc,
                op,
                args.vd,
                args.vs,
                args.vt,
                args.el,
            });

            const cp2 = &core.cp2;
            const lhs = cp2.get(args.vs);
            const rhs = cp2.broadcast(args.vt, args.el);
            cp2.set(args.vd, computeOp(op, cp2, lhs, rhs));
        }
    }.instr;
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

fn computeOp(
    comptime op: ComputeOp,
    cp2: *Cp2,
    lhs: @Vector(8, u16),
    rhs: @Vector(8, u16),
) @Vector(8, u16) {
    return switch (comptime op) {
        .VMULF => blk: {
            const result = fw.num.signExtend(@Vector(8, i32), lhs) *
                fw.num.signExtend(@Vector(8, i32), rhs);

            cp2.acc = @splat(0x8000);
            cp2.acc +%= fw.num.signExtend(@Vector(8, u64), result) << @splat(1);

            break :blk @truncate(clampSigned(cp2.acc) >> @splat(16));
        },
        .VMULU => blk: {
            const result = fw.num.signExtend(@Vector(8, i32), lhs) *
                fw.num.signExtend(@Vector(8, i32), rhs);

            cp2.acc = @splat(0x8000);
            cp2.acc +%= fw.num.signExtend(@Vector(8, u64), result) << @splat(1);

            break :blk @truncate(clampUnsigned(cp2.acc) >> @splat(16));
        },
        .VMUDL => blk: {
            const result = @as(@Vector(8, u32), lhs) *
                @as(@Vector(8, u32), rhs);

            cp2.acc = result >> @splat(16);

            break :blk @truncate(cp2.acc);
        },
        .VMUDM => blk: {
            const result = fw.num.signExtend(@Vector(8, i32), lhs) *
                fw.num.zeroExtend(@Vector(8, i32), rhs);

            cp2.acc = fw.num.signExtend(@Vector(8, u64), result);

            break :blk @truncate(cp2.acc >> @splat(16));
        },
        .VMUDN => blk: {
            const result = fw.num.zeroExtend(@Vector(8, i32), lhs) *
                fw.num.signExtend(@Vector(8, i32), rhs);

            cp2.acc = fw.num.signExtend(@Vector(8, u64), result);

            break :blk @truncate(cp2.acc);
        },
        .VMUDH => blk: {
            const result = fw.num.signExtend(@Vector(8, i32), lhs) *
                fw.num.signExtend(@Vector(8, i32), rhs);

            cp2.acc = fw.num.signExtend(@Vector(8, u64), result) << @splat(16);

            break :blk @truncate(clampSigned(cp2.acc) >> @splat(16));
        },
        .VMACF => blk: {
            const result = fw.num.signExtend(@Vector(8, i32), lhs) *
                fw.num.signExtend(@Vector(8, i32), rhs);

            cp2.acc +%= fw.num.signExtend(@Vector(8, u64), result) << @splat(1);

            break :blk @truncate(clampSigned(cp2.acc) >> @splat(16));
        },
        .VMACU => blk: {
            const result = fw.num.signExtend(@Vector(8, i32), lhs) *
                fw.num.signExtend(@Vector(8, i32), rhs);

            cp2.acc +%= fw.num.signExtend(@Vector(8, u64), result) << @splat(1);

            break :blk @truncate(clampUnsigned(cp2.acc) >> @splat(16));
        },
        .VMADL => blk: {
            const result = @as(@Vector(8, u32), lhs) *
                @as(@Vector(8, u32), rhs);

            cp2.acc +%= result >> @splat(16);

            break :blk @truncate(clampSigned(cp2.acc));
        },
        .VMADM => blk: {
            const result = fw.num.signExtend(@Vector(8, i32), lhs) *
                fw.num.zeroExtend(@Vector(8, i32), rhs);

            cp2.acc +%= fw.num.signExtend(@Vector(8, u64), result);

            break :blk @truncate(clampSigned(cp2.acc) >> @splat(16));
        },
        .VMADN => blk: {
            const result = fw.num.zeroExtend(@Vector(8, i32), lhs) *
                fw.num.signExtend(@Vector(8, i32), rhs);

            cp2.acc +%= fw.num.signExtend(@Vector(8, u64), result);

            break :blk @truncate(clampSigned(cp2.acc));
        },
        .VMADH => blk: {
            const result = fw.num.signExtend(@Vector(8, i32), lhs) *
                fw.num.signExtend(@Vector(8, i32), rhs);

            cp2.acc +%= fw.num.signExtend(@Vector(8, u64), result) << @splat(16);

            break :blk @truncate(clampSigned(cp2.acc) >> @splat(16));
        },
        .VADD => blk: {
            const result = fw.num.signExtend(@Vector(8, i32), lhs) +%
                fw.num.signExtend(@Vector(8, i32), rhs) +%
                @as(@Vector(8, i32), @intFromBool(cp2.carry));

            cp2.setAccLow(fw.num.truncate(@Vector(8, u16), result));

            cp2.carry = v_false;
            cp2.not_equal = v_false;

            break :blk fw.num.truncate(@Vector(8, u16), clampResult(result));
        },
        .VSUB => blk: {
            const result = fw.num.signExtend(@Vector(8, i32), lhs) -%
                fw.num.signExtend(@Vector(8, i32), rhs) -%
                @as(@Vector(8, i32), @intFromBool(cp2.carry));

            cp2.setAccLow(fw.num.truncate(@Vector(8, u16), result));

            cp2.carry = v_false;
            cp2.not_equal = v_false;

            break :blk fw.num.truncate(@Vector(8, u16), clampResult(result));
        },
        .VABS => blk: {
            const pos = @select(u16, lhs > zero, rhs, zero);
            const neg = -%rhs;
            const neg_clamped = @select(u16, rhs == i16_min, i16_max, neg);

            cp2.setAccLow(@select(u16, lhs < i16_min, pos, neg));

            break :blk @select(u16, lhs < i16_min, pos, neg_clamped);
        },
        .VADDC => blk: {
            const result, const overflow = @addWithOverflow(lhs, rhs);

            cp2.setAccLow(result);

            cp2.carry = overflow != zero;
            cp2.not_equal = v_false;

            break :blk result;
        },
        .VSUBC => blk: {
            const result, const overflow = @subWithOverflow(lhs, rhs);

            cp2.setAccLow(result);

            cp2.carry = overflow != zero;
            cp2.not_equal = result != zero;

            break :blk result;
        },
        .VAND => blk: {
            const result = lhs & rhs;
            cp2.setAccLow(result);
            break :blk result;
        },
        .VNAND => blk: {
            const result = ~(lhs & rhs);
            cp2.setAccLow(result);
            break :blk result;
        },
        .VOR => blk: {
            const result = lhs | rhs;
            cp2.setAccLow(result);
            break :blk result;
        },
        .VNOR => blk: {
            const result = ~(lhs | rhs);
            cp2.setAccLow(result);
            break :blk result;
        },
        .VXOR => blk: {
            const result = lhs ^ rhs;
            cp2.setAccLow(result);
            break :blk result;
        },
        .VNXOR => blk: {
            const result = ~(lhs ^ rhs);
            cp2.setAccLow(result);
            break :blk result;
        },
        .VEQ => blk: {
            const condition = @select(bool, lhs == rhs, cp2.not_equal == v_false, v_false);
            break :blk select(cp2, condition, lhs, rhs);
        },
        .VNE => blk: {
            const condition = @select(bool, lhs == rhs, cp2.not_equal, v_true);
            break :blk select(cp2, condition, lhs, rhs);
        },
        .VGE => blk: {
            const flags = @select(bool, cp2.carry, !cp2.not_equal, v_true);
            const le = @select(bool, lhs == rhs, flags, v_false);
            const condition = @select(bool, fw.num.signed(lhs) > fw.num.signed(rhs), v_true, le);
            break :blk select(cp2, condition, lhs, rhs);
        },
        .VLT => blk: {
            const flags = @select(bool, cp2.carry, cp2.not_equal, v_false);
            const le = @select(bool, lhs == rhs, flags, v_false);
            const condition = @select(bool, fw.num.signed(lhs) < fw.num.signed(rhs), v_true, le);
            break :blk select(cp2, condition, lhs, rhs);
        },
        .VCL => blk: {
            const cmp_result = @as(@Vector(8, u32), lhs) + @as(@Vector(8, u32), rhs);
            const limit: @Vector(8, u32) = @splat(0x0001_0000);

            const ext = @select(bool, cp2.compare_ext, cmp_result <= limit, cmp_result == zero);
            const compare = @select(bool, cp2.not_equal, cp2.compare, ext);
            cp2.compare = @select(bool, cp2.carry, compare, cp2.compare);

            const clip_compare = @select(bool, cp2.not_equal, cp2.clip_compare, lhs >= rhs);
            cp2.clip_compare = @select(bool, cp2.carry, cp2.clip_compare, clip_compare);

            const lt_result = @select(u16, cp2.compare, -%rhs, lhs);
            const ge_result = @select(u16, cp2.clip_compare, rhs, lhs);
            const result = @select(u16, cp2.carry, lt_result, ge_result);

            cp2.setAccLow(result);

            cp2.carry = v_false;
            cp2.not_equal = v_false;
            cp2.compare_ext = v_false;

            break :blk result;
        },
        .VCH => blk: {
            cp2.carry = fw.num.signed(lhs ^ rhs) < fw.num.signed(zero);

            const cmp_value = @select(u16, cp2.carry, lhs +% rhs, lhs -% rhs);

            cp2.not_equal = @select(bool, cmp_value != zero, lhs != ~rhs, v_false);

            cp2.compare = @select(
                bool,
                cp2.carry,
                fw.num.signed(cmp_value) <= fw.num.signed(zero),
                fw.num.signed(rhs) < fw.num.signed(zero),
            );

            cp2.clip_compare = @select(
                bool,
                cp2.carry,
                fw.num.signed(rhs) < fw.num.signed(zero),
                fw.num.signed(cmp_value) >= fw.num.signed(zero),
            );

            cp2.compare_ext = @select(bool, cp2.carry, cmp_value == u16_max, v_false);

            const lt_result = @select(u16, cp2.compare, -%rhs, lhs);
            const ge_result = @select(u16, cp2.clip_compare, rhs, lhs);
            const result = @select(u16, cp2.carry, lt_result, ge_result);

            cp2.setAccLow(result);

            break :blk result;
        },
        .VCR => blk: {
            const carry = fw.num.signed(lhs ^ rhs) < fw.num.signed(zero);
            const cmp_value = @select(u16, carry, lhs +% rhs, lhs -% rhs);

            cp2.clip_compare = @select(
                bool,
                carry,
                fw.num.signed(rhs) < fw.num.signed(zero),
                fw.num.signed(cmp_value) >= fw.num.signed(zero),
            );

            cp2.compare = @select(
                bool,
                carry,
                fw.num.signed(cmp_value) < fw.num.signed(zero),
                fw.num.signed(rhs) < fw.num.signed(zero),
            );

            const lt_result = @select(u16, cp2.compare, ~rhs, lhs);
            const ge_result = @select(u16, cp2.clip_compare, rhs, lhs);
            const result = @select(u16, carry, lt_result, ge_result);

            cp2.setAccLow(result);

            cp2.carry = v_false;
            cp2.not_equal = v_false;
            cp2.compare_ext = v_false;

            break :blk result;
        },
        .VMRG => blk: {
            const result = @select(u16, cp2.compare, lhs, rhs);

            cp2.setAccLow(result);

            cp2.carry = v_false;
            cp2.not_equal = v_false;

            break :blk result;
        },
    };
}

fn select(
    cp2: *Cp2,
    condition: @Vector(8, bool),
    lhs: @Vector(8, u16),
    rhs: @Vector(8, u16),
) @Vector(8, u16) {
    const result = @select(u16, condition, lhs, rhs);

    cp2.setAccLow(result);

    cp2.carry = v_false;
    cp2.not_equal = v_false;
    cp2.compare = condition;
    cp2.clip_compare = v_false;

    return result;
}

fn clampSigned(acc: @Vector(8, u64)) @Vector(8, u64) {
    const truncated = fw.num.signed(acc) << @splat(16) >> @splat(16);

    return @bitCast(std.math.clamp(
        truncated,
        @as(@Vector(8, i64), @splat(std.math.minInt(i32))),
        @as(@Vector(8, i64), @splat(std.math.maxInt(i32))),
    ));
}

fn clampUnsigned(acc: @Vector(8, u64)) @Vector(8, u64) {
    const mask: @Vector(8, u64) = @splat(0x0000_ffff_ffff_ffff);
    const truncated = acc & mask;

    const clipped = @select(
        u64,
        truncated < @as(@Vector(8, u64), @splat(0x8000_0000)),
        truncated,
        @as(@Vector(8, u64), @splat(std.math.maxInt(u64))),
    );

    return @select(
        u64,
        truncated < @as(@Vector(8, u64), @splat(0x8000_0000_0000)),
        clipped,
        @as(@Vector(8, u64), @splat(0)),
    );
}

fn clampResult(value: @Vector(8, i32)) @Vector(8, i32) {
    return @bitCast(std.math.clamp(
        value,
        @as(@Vector(8, i32), @splat(std.math.minInt(i16))),
        @as(@Vector(8, i32), @splat(std.math.maxInt(i16))),
    ));
}
