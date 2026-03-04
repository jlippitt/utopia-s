const std = @import("std");
const fw = @import("framework");
const Core = @import("../../Cpu.zig");
const Cp1 = @import("../Cp1.zig");

pub const LoadOp = enum {
    LWC1,
    LDC1,

    fn alignMask(comptime op: @This()) u32 {
        return switch (comptime op) {
            .LWC1 => 3,
            .LDC1 => 7,
        };
    }
};

pub fn load(comptime op: LoadOp, core: *Core, word: u32) void {
    if (!core.cp0.cp1Usable()) {
        @branchHint(.unlikely);
        core.except(.{ .coprocessor_unusable = 1 });
        return;
    }

    const args: Cp1.IType = @bitCast(word);
    const offset = fw.num.signExtend(u32, args.imm);

    fw.log.trace("{X:08}: {t} {t}, {d}({t})", .{
        core.pc,
        op,
        args.ft,
        fw.num.signed(offset),
        args.rs,
    });

    const vaddr = @as(u32, @truncate(core.get(args.rs))) +% offset;
    const paddr = core.mapAddress(vaddr, false) orelse return;

    if ((paddr & op.alignMask()) != 0) {
        @branchHint(.cold);
        fw.log.todo("CPU alignment exceptions", .{});
    }

    switch (comptime op) {
        .LWC1 => core.cp1.set(.W, args.ft, @bitCast(core.readWord(paddr))),
        .LDC1 => core.cp1.set(.L, args.ft, @bitCast(core.readDoubleWord(paddr))),
    }
}

pub const StoreOp = enum {
    SWC1,
    SDC1,

    fn alignMask(comptime op: @This()) u32 {
        return switch (comptime op) {
            .SWC1 => 3,
            .SDC1 => 7,
        };
    }
};

pub fn store(comptime op: StoreOp, core: *Core, word: u32) void {
    if (!core.cp0.cp1Usable()) {
        @branchHint(.unlikely);
        core.except(.{ .coprocessor_unusable = 1 });
        return;
    }

    const args: Cp1.IType = @bitCast(word);
    const offset = fw.num.signExtend(u32, args.imm);

    fw.log.trace("{X:08}: {t} {t}, {d}({t})", .{
        core.pc,
        op,
        args.ft,
        fw.num.signed(offset),
        args.rs,
    });

    const vaddr = @as(u32, @truncate(core.get(args.rs))) +% offset;
    const paddr = core.mapAddress(vaddr, true) orelse return;

    if ((paddr & op.alignMask()) != 0) {
        @branchHint(.cold);
        fw.log.todo("CPU alignment exceptions", .{});
    }

    switch (comptime op) {
        .SWC1 => core.writeWord(
            paddr,
            @bitCast(core.cp1.get(.W, args.ft)),
            std.math.maxInt(u32),
        ),
        .SDC1 => core.writeDoubleWord(
            paddr,
            @bitCast(core.cp1.get(.L, args.ft)),
            std.math.maxInt(u64),
        ),
    }
}
