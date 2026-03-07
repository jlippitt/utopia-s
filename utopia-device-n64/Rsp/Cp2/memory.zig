const std = @import("std");
const fw = @import("framework");
const Core = @import("../Core.zig");
const Cp2 = @import("../Cp2.zig");

const Args = packed struct(u32) {
    imm: u7,
    el: u4,
    rd: u5,
    vt: Cp2.Register,
    rs: Core.Register,
    opcode: u6,
};

pub const MemoryOp = enum {
    BV,
    SV,
    LV,
    DV,
    QV,
    RV,
    PV,
    UV,
    TV,

    fn shift(comptime op: @This()) comptime_int {
        return switch (comptime op) {
            .BV => 0,
            .SV => 1,
            .LV => 2,
            .DV, .PV, .UV => 3,
            .QV, .RV, .TV => 4,
        };
    }
};

pub fn load(comptime op: MemoryOp) Core.Instruction {
    return struct {
        fn instr(core: *Core, word: u32) void {
            const args: Args = @bitCast(word);

            const offset = fw.num.signExtend(u12, args.imm) << op.shift();

            fw.log.trace("{X:03}: L{t} {t}[E:{d}], {d}({t})", .{
                core.pc,
                op,
                args.vt,
                args.el,
                fw.num.signed(offset),
                args.rs,
            });

            const address = @as(u12, @truncate(core.get(args.rs))) +% offset;

            switch (comptime op) {
                .BV => core.cp2.setEl(u8, args.vt, args.el, core.readData(u8, address)),
                .SV => core.cp2.setEl(u16, args.vt, args.el, core.readData(u16, address)),
                .LV => core.cp2.setEl(u32, args.vt, args.el, core.readData(u32, address)),
                .DV => core.cp2.setEl(u64, args.vt, args.el, core.readData(u64, address)),
                .QV => blk: {
                    if (args.el == 0 and (address & 15) == 0) {
                        @branchHint(.likely);
                        core.cp2.set(args.vt, @bitCast(core.readDataAligned(u128, address)));
                        break :blk;
                    }

                    const value = core.readDataAligned(u128, address & ~@as(u12, 15));
                    const size = 8 + (15 - (address & 15)) * 8;
                    const shift = 128 - (@as(i32, size) + @as(i32, args.el) * 8);
                    const mask = @as(u128, std.math.maxInt(u128)) >> @intCast(128 - size);

                    var result: u128 = @bitCast(core.cp2.get(args.vt));
                    result &= ~std.math.shl(u128, mask, shift);
                    result |= std.math.shl(u128, value & mask, shift);
                    core.cp2.set(args.vt, @bitCast(result));
                },
                .RV => {
                    const value = core.readDataAligned(u128, address & ~@as(u12, 15));
                    const size = (15 - (address & 15 ^ 15)) * 8;
                    const shift = 128 - @as(i32, size) + @as(i32, args.el) * 8;
                    const mask = std.math.maxInt(u128);

                    var result: u128 = @bitCast(core.cp2.get(args.vt));
                    result &= ~std.math.shr(u128, mask, shift);
                    result |= std.math.shr(u128, value, shift);
                    core.cp2.set(args.vt, @bitCast(result));
                },
                .PV => loadPacked(.signed, core, address, args.vt, args.el),
                .UV => loadPacked(.unsigned, core, address, args.vt, args.el),
                .TV => {
                    const start = address & ~@as(u12, 7);
                    const base_offset = @as(u4, @intCast(address & 8)) +% args.el;

                    var index: u4 = 0;

                    while (true) {
                        const reg_index = (@intFromEnum(args.vt) & ~@as(u5, 7)) +%
                            (((index +% args.el) >> 1) & 7);

                        inline for (0..2) |_| {
                            const byte_address = start +% (base_offset +% index);
                            const byte_value = core.readData(u8, byte_address);
                            core.cp2.setEl(u8, @enumFromInt(reg_index), index, byte_value);
                            index +%= 1;
                        }

                        if (index == 0) {
                            break;
                        }
                    }
                },
            }
        }
    }.instr;
}

pub fn store(comptime op: MemoryOp) Core.Instruction {
    return struct {
        fn instr(core: *Core, word: u32) void {
            const args: Args = @bitCast(word);
            const offset = fw.num.signExtend(u12, args.imm) << op.shift();

            fw.log.trace("{X:03}: S{t} {t}[E:{d}], {d}({t})", .{
                core.pc,
                op,
                args.vt,
                args.el,
                fw.num.signed(offset),
                args.rs,
            });

            const address = @as(u12, @truncate(core.get(args.rs))) +% offset;

            switch (comptime op) {
                .BV => core.writeData(u8, address, core.cp2.getEl(u8, args.vt, args.el)),
                .SV => core.writeData(u16, address, core.cp2.getEl(u16, args.vt, args.el)),
                .LV => core.writeData(u32, address, core.cp2.getEl(u32, args.vt, args.el)),
                .DV => core.writeData(u64, address, core.cp2.getEl(u64, args.vt, args.el)),
                .QV => blk: {
                    if (args.el == 0 and (address & 15) == 0) {
                        @branchHint(.likely);
                        core.writeDataAligned(u128, address, @bitCast(core.cp2.get(args.vt)));
                        break :blk;
                    }

                    const shift: u7 = @intCast((address & 15) * 8);
                    const value = core.cp2.getEl(u128, args.vt, args.el);
                    const mask: u128 = std.math.maxInt(u128);

                    core.writeDataAlignedMasked(
                        u128,
                        address & ~@as(u12, 15),
                        value >> shift,
                        mask >> shift,
                    );
                },
                .RV => {
                    const shift: i32 = 128 - (address & 15) * 8;
                    const value = core.cp2.getEl(u128, args.vt, args.el);
                    const mask: u128 = std.math.maxInt(u128);

                    core.writeDataAlignedMasked(
                        u128,
                        address & ~@as(u12, 15),
                        std.math.shl(u128, value, shift),
                        std.math.shl(u128, mask, shift),
                    );
                },
                .PV => storePacked(.signed, core, address, args.vt, args.el),
                .UV => storePacked(.unsigned, core, address, args.vt, args.el),
                .TV => {
                    const start = address & ~@as(u12, 7);
                    const el = args.el & ~@as(u4, 1);
                    const base_offset = @as(u4, @intCast(address & 7)) -% el;

                    var index: u4 = 0;

                    while (true) {
                        const reg_index = (@intFromEnum(args.vt) & ~@as(u5, 7)) +% (index >> 1);

                        inline for (0..2) |_| {
                            const byte_value = core.cp2.getEl(u8, @enumFromInt(reg_index), index -% el);
                            const byte_address = start +% (base_offset +% index);
                            core.writeData(u8, byte_address, byte_value);
                            index +%= 1;
                        }

                        if (index == 0) {
                            break;
                        }
                    }
                },
            }
        }
    }.instr;
}

fn loadPacked(
    comptime signedness: std.builtin.Signedness,
    core: *Core,
    address: u12,
    vt: Cp2.Register,
    el: u4,
) void {
    const shift: u4 = switch (comptime signedness) {
        .signed => 8,
        .unsigned => 7,
    };

    const start = address & ~@as(u12, 7);
    const base_offset = @as(u4, @intCast(address & 7)) -% el;

    for (0..8) |index| {
        const byte_address = start +% (base_offset +% @as(u4, @intCast(index)));
        const byte_value = core.readData(u8, byte_address);
        core.cp2.setLane(vt, index, @as(u16, byte_value) << shift);
    }
}

fn storePacked(
    comptime signedness: std.builtin.Signedness,
    core: *Core,
    address: u12,
    vt: Cp2.Register,
    el: u4,
) void {
    const shift_lo: u4, const shift_hi: u4 = switch (comptime signedness) {
        .signed => .{ 8, 7 },
        .unsigned => .{ 7, 8 },
    };

    for (0..8) |index| {
        const byte_offset = @as(u4, @intCast(index)) +% el;

        const byte_value: u8 = @truncate(if (byte_offset < 8)
            core.cp2.getLane(vt, byte_offset) >> shift_lo
        else
            core.cp2.getLane(vt, byte_offset & 7) >> shift_hi);

        core.writeData(u8, address +% @as(u12, @intCast(index)), byte_value);
    }
}
