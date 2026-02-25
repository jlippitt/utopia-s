const std = @import("std");
const fw = @import("framework");
const Core = @import("../Cpu.zig");

pub const LoadOp = enum {
    LW,
    LWU,

    fn alignMask(comptime op: @This()) u32 {
        return switch (comptime op) {
            .LW, .LWU => 3,
        };
    }
};

pub fn load(comptime op: LoadOp, comptime bus: Core.Bus, core: *Core, word: u32) void {
    const args: Core.IType = @bitCast(word);
    const offset = fw.num.signExtend(u32, args.imm);

    fw.log.trace("{X:08}: {t} {t}, {d}({t})", .{
        core.pc,
        op,
        args.rt,
        @as(i32, @bitCast(offset)),
        args.rs,
    });

    const vaddr = @as(u32, @truncate(core.get(args.rs))) +% offset;
    const paddr = core.mapAddress(vaddr) orelse return;

    if ((paddr & op.alignMask()) != 0) {
        @branchHint(.cold);
        fw.log.todo("CPU alignment exceptions", .{});
    }

    core.set(args.rt, switch (comptime op) {
        .LW => fw.num.signExtend(u64, core.readWord(bus, paddr)),
        .LWU => fw.num.zeroExtend(u64, core.readWord(bus, paddr)),
    });
}

pub const StoreOp = enum {
    SW,

    fn alignMask(comptime op: @This()) u32 {
        return switch (comptime op) {
            .SW => 3,
        };
    }
};

pub fn store(comptime op: StoreOp, comptime bus: Core.Bus, core: *Core, word: u32) void {
    const args: Core.IType = @bitCast(word);
    const offset = fw.num.signExtend(u32, args.imm);

    fw.log.trace("{X:08}: {t} {t}, {d}({t})", .{
        core.pc,
        op,
        args.rt,
        @as(i32, @bitCast(offset)),
        args.rs,
    });

    const vaddr = @as(u32, @truncate(core.get(args.rs))) +% offset;
    const paddr = core.mapAddress(vaddr) orelse return;

    if ((paddr & op.alignMask()) != 0) {
        @branchHint(.cold);
        fw.log.todo("CPU alignment exceptions", .{});
    }

    const value = core.get(args.rt);

    switch (comptime op) {
        .SW => core.writeWord(bus, paddr, @truncate(value), std.math.maxInt(u32)),
    }
}

pub fn cache(core: *Core, word: u32) void {
    _ = word;
    fw.log.trace("{X:08}: CACHE", .{core.pc});
    // TODO
}
