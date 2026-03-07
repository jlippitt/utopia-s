const std = @import("std");
const fw = @import("framework");
const Core = @import("../Core.zig");
const Cp2 = @import("../Cp2.zig");

const Args = packed struct(u32) {
    funct: u6,
    vd: Cp2.Register,
    vd_el: u5,
    vt: Cp2.Register,
    vt_el: u4,
    __: u1,
    opcode: u6,
};

pub fn vmov(core: *Core, word: u32) void {
    const args: Args = @bitCast(word);

    fw.log.trace("{X:03}: VMOV {t}[E:{d}], {t}[E:{d}]", .{
        core.pc,
        args.vd,
        args.vd_el,
        args.vt,
        args.vt_el,
    });

    const cp2 = &core.cp2;

    cp2.setAccLow(cp2.broadcast(args.vt, args.vt_el));

    // Weird lane shenanigans that only occur on VMOV
    const vt_lane = switch (args.vt_el) {
        0...1 => args.vd_el & 7,
        2...3 => (args.vd_el & 6) | (args.vt_el & 1),
        4...7 => (args.vd_el & 4) | (args.vt_el & 3),
        else => args.vt_el & 7,
    };

    const vd_lane = args.vd_el & 7;

    cp2.setLane(args.vd, vd_lane, cp2.getLane(args.vt, vt_lane));
}

const ReciprocalFunc = enum {
    reciprocal,
    inv_sqrt,
};

const ReciprocalStage = enum {
    calc,
    calc_long,
    extract_high,
};

pub const ReciprocalOp = enum {
    VRCP,
    VRCPL,
    VRCPH,
    VRSQ,
    VRSQL,
    VRSQH,

    fn func(comptime op: @This()) ReciprocalFunc {
        return switch (comptime op) {
            .VRCP, .VRCPL, .VRCPH => .reciprocal,
            .VRSQ, .VRSQL, .VRSQH => .inv_sqrt,
        };
    }

    fn stage(comptime op: @This()) ReciprocalStage {
        return switch (comptime op) {
            .VRCP, .VRSQ => .calc,
            .VRCPL, .VRSQL => .calc_long,
            .VRCPH, .VRSQH => .extract_high,
        };
    }
};

pub fn reciprocal(comptime op: ReciprocalOp) Core.Instruction {
    return struct {
        fn instr(core: *Core, word: u32) void {
            const args: Args = @bitCast(word);

            fw.log.trace("{X:03}: {t} {t}[E:{d}], {t}[E:{d}]", .{
                core.pc,
                op,
                args.vd,
                args.vd_el,
                args.vt,
                args.vt_el,
            });

            const cp2 = &core.cp2;

            cp2.setAccLow(cp2.broadcast(args.vt, args.vt_el));

            const vt_lane = args.vt_el & 7;
            const vd_lane = args.vd_el & 7;

            const value = cp2.getLane(args.vt, vt_lane);

            const result: u16 = switch (comptime op.stage()) {
                .calc => calculate(op.func(), cp2, fw.num.signed(value)),
                .calc_long => blk: {
                    const input: i32 = if (cp2.rcp_high)
                        fw.num.signed(cp2.rcp_in | value)
                    else
                        fw.num.signed(value);

                    break :blk calculate(op.func(), cp2, input);
                },
                .extract_high => blk: {
                    cp2.rcp_in = @as(u32, value) << 16;
                    cp2.rcp_high = true;
                    break :blk @truncate(cp2.rcp_out >> 16);
                },
            };

            cp2.setLane(args.vd, vd_lane, result);
        }
    }.instr;
}

fn calculate(comptime op: ReciprocalFunc, cp2: *Cp2, input: i32) u16 {
    const sign_bit = input >> 31;
    const masked = (input ^ sign_bit) - if (input > std.math.minInt(i16)) sign_bit else 0;

    var result: u32 = undefined;

    if (masked == 0) {
        @branchHint(.unlikely);
        result = 0x7fff_ffff;
    } else if (input == std.math.minInt(i16)) {
        @branchHint(.unlikely);
        result = 0xffff_0000;
    } else {
        const index_shift: u5 = @intCast(@clz(masked));
        const index = fw.num.unsigned(((masked << index_shift) & 0x7fc0_0000) >> 22);

        const value = @as(i32, 0x1_0000) | fw.num.zeroExtend(i32, switch (comptime op) {
            .reciprocal => reciprocal_table[index],
            .inv_sqrt => inv_sqrt_table[(index & 0x1fe) | (index_shift & 1)],
        });

        const value_shift = (31 - index_shift) >> @intFromBool(comptime op == .inv_sqrt);

        result = @bitCast((((value << 14) >> value_shift) ^ sign_bit));
    }

    cp2.rcp_out = result;
    cp2.rcp_high = false;

    return @truncate(result);
}

const reciprocal_table: [512]u16 = blk: {
    var table: [512]u16 = undefined;

    for (&table, 0..) |*value, index| {
        if (index == 0) {
            value.* = std.math.maxInt(u16);
            continue;
        }

        value.* = @truncate(((@as(u64, 1) << 34) / (@as(u64, index) + 512) + 1) >> 8);
    }

    break :blk table;
};

var inv_sqrt_table: [512]u16 = undefined;

// This does not work at comptime (too many branches? or compiler bug?)
pub fn initInvSqrtTable() void {
    for (&inv_sqrt_table, 0..) |*value, index| {
        const input = (@as(u64, index) + 512) >> @intCast(index & 1);
        const threshold = @as(u64, 1) << 44;

        var result = @as(u64, 1) << 17;

        while ((input * (result + 1) * (result + 1)) < threshold) {
            result += 1;
        }

        value.* = @truncate(result >> 1);
    }
}
