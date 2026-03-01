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

    fn shift(comptime op: @This()) comptime_int {
        return switch (comptime op) {
            .BV => 0,
            .SV => 1,
            .LV => 2,
            .DV => 3,
            .QV => 4,
        };
    }
};

pub fn load(comptime op: MemoryOp, core: *Core, word: u32) void {
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
                break :blk core.cp2.set(args.vt, @bitCast(core.readData(u128, address)));
            }

            fw.log.todo("Misaligned LQV", .{});
        },
    }
}

pub fn store(comptime op: MemoryOp, core: *Core, word: u32) void {
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
                break :blk core.writeData(u128, address, @bitCast(core.cp2.get(args.vt)));
            }

            fw.log.todo("Misaligned SQV", .{});
        },
    }
}
