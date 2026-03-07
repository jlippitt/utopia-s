const std = @import("std");
const fw = @import("framework");
const Core = @import("../Cpu.zig");

pub const LoadOp = enum {
    LB,
    LBU,
    LH,
    LHU,
    LW,
    LWU,
    LWL,
    LWR,
    LD,
    LDL,
    LDR,
    LL,
    LLD,

    fn alignMask(comptime op: @This()) u32 {
        return switch (comptime op) {
            .LB, .LBU, .LWL, .LWR, .LDL, .LDR => 0,
            .LH, .LHU => 1,
            .LW, .LWU, .LL => 3,
            .LD, .LLD => 7,
        };
    }
};

pub fn load(comptime op: LoadOp) Core.Instruction {
    return struct {
        fn instr(core: *Core, word: u32) void {
            const args: Core.IType = @bitCast(word);
            const offset = fw.num.signExtend(u32, args.imm);

            fw.log.trace("{X:08}: {t} {t}, {d}({t})", .{
                core.pc,
                op,
                args.rt,
                fw.num.signed(offset),
                args.rs,
            });

            const vaddr = @as(u32, @truncate(core.get(args.rs))) +% offset;
            const paddr = core.mapAddress(vaddr, false) orelse return;

            if ((paddr & op.alignMask()) != 0) {
                @branchHint(.cold);
                fw.log.todo("CPU alignment exceptions", .{});
            }

            core.set(args.rt, switch (comptime op) {
                .LB => blk: {
                    const input = core.readWord(paddr);
                    const shift: u5 = @intCast((paddr & 3 ^ 3) * 8);
                    break :blk fw.num.signExtend(u64, @as(u8, @truncate(input >> shift)));
                },
                .LBU => blk: {
                    const input = core.readWord(paddr);
                    const shift: u5 = @intCast((paddr & 3 ^ 3) * 8);
                    break :blk fw.num.zeroExtend(u64, @as(u8, @truncate(input >> shift)));
                },
                .LH => blk: {
                    const input = core.readWord(paddr);
                    const shift: u5 = @intCast((paddr & 2 ^ 2) * 8);
                    break :blk fw.num.signExtend(u64, @as(u16, @truncate(input >> shift)));
                },
                .LHU => blk: {
                    const input = core.readWord(paddr);
                    const shift: u5 = @intCast((paddr & 2 ^ 2) * 8);
                    break :blk fw.num.zeroExtend(u64, @as(u16, @truncate(input >> shift)));
                },
                .LW => fw.num.signExtend(u64, core.readWord(paddr)),
                .LWU => fw.num.zeroExtend(u64, core.readWord(paddr)),
                .LWL => blk: {
                    const input = core.readWord(paddr & ~@as(u32, 3));
                    const shift: u5 = @intCast((paddr & 3) * 8);
                    const old: u32 = @truncate(core.get(args.rt));
                    const new = input << shift;
                    const mask = @as(u32, std.math.maxInt(u32)) << shift;
                    break :blk fw.num.signExtend(u64, (old & ~mask) | (new & mask));
                },
                .LWR => blk: {
                    const input = core.readWord(paddr & ~@as(u32, 3));
                    const shift: u5 = @intCast((paddr & 3 ^ 3) * 8);
                    const old: u32 = @truncate(core.get(args.rt));
                    const new = input >> shift;
                    const mask = @as(u32, std.math.maxInt(u32)) >> shift;
                    break :blk fw.num.signExtend(u64, (old & ~mask) | (new & mask));
                },
                .LD => core.readDoubleWord(paddr),
                .LDL => blk: {
                    const input = core.readDoubleWord(paddr & ~@as(u32, 7));
                    const shift: u6 = @intCast((paddr & 7) * 8);
                    const old = core.get(args.rt);
                    const new = input << shift;
                    const mask = @as(u64, std.math.maxInt(u64)) << shift;
                    break :blk (old & ~mask) | (new & mask);
                },
                .LDR => blk: {
                    const input = core.readDoubleWord(paddr & ~@as(u32, 7));
                    const shift: u6 = @intCast((paddr & 7 ^ 7) * 8);
                    const old = core.get(args.rt);
                    const new = input >> shift;
                    const mask = @as(u64, std.math.maxInt(u64)) >> shift;
                    break :blk (old & ~mask) | (new & mask);
                },
                .LL => blk: {
                    core.cp0.setLLAddr(paddr >> 4);
                    core.ll_bit = true;
                    break :blk fw.num.signExtend(u64, core.readWord(paddr));
                },
                .LLD => blk: {
                    core.cp0.setLLAddr(paddr >> 4);
                    core.ll_bit = true;
                    break :blk core.readDoubleWord(paddr);
                },
            });
        }
    }.instr;
}

pub const StoreOp = enum {
    SB,
    SH,
    SW,
    SWL,
    SWR,
    SD,
    SDL,
    SDR,
    SC,
    SCD,

    fn alignMask(comptime op: @This()) u32 {
        return switch (comptime op) {
            .SB, .SWL, .SWR, .SDL, .SDR => 0,
            .SH => 1,
            .SW, .SC => 3,
            .SD, .SCD => 7,
        };
    }
};

pub fn store(comptime op: StoreOp) Core.Instruction {
    return struct {
        fn instr(core: *Core, word: u32) void {
            const args: Core.IType = @bitCast(word);
            const offset = fw.num.signExtend(u32, args.imm);

            fw.log.trace("{X:08}: {t} {t}, {d}({t})", .{
                core.pc,
                op,
                args.rt,
                fw.num.signed(offset),
                args.rs,
            });

            const vaddr = @as(u32, @truncate(core.get(args.rs))) +% offset;
            const paddr = core.mapAddress(vaddr, true) orelse return;

            if ((paddr & op.alignMask()) != 0) {
                @branchHint(.cold);
                fw.log.todo("CPU alignment exceptions", .{});
            }

            const value = core.get(args.rt);

            switch (comptime op) {
                .SB => {
                    const shift: u5 = @intCast((paddr & 3 ^ 3) * 8);
                    const output = @as(u32, @truncate(value)) << shift;
                    const mask = @as(u32, @truncate(std.math.maxInt(u8))) << shift;
                    core.writeWord(paddr, output, mask);
                },
                .SH => {
                    const shift: u5 = @intCast((paddr & 2 ^ 2) * 8);
                    const output = @as(u32, @truncate(value)) << shift;
                    const mask = @as(u32, @truncate(std.math.maxInt(u16))) << shift;
                    core.writeWord(paddr, output, mask);
                },
                .SW => core.writeWord(paddr, @truncate(value), std.math.maxInt(u32)),
                .SWL => {
                    const shift: u5 = @intCast((paddr & 3) * 8);
                    const output = @as(u32, @truncate(value)) >> shift;
                    const mask = @as(u32, std.math.maxInt(u32)) >> shift;
                    core.writeWord(paddr & ~@as(u32, 3), output, mask);
                },
                .SWR => {
                    const shift: u5 = @intCast((paddr & 3 ^ 3) * 8);
                    const output = @as(u32, @truncate(value)) << shift;
                    const mask = @as(u32, std.math.maxInt(u32)) << shift;
                    core.writeWord(paddr & ~@as(u32, 3), output, mask);
                },
                .SD => core.writeDoubleWord(paddr, value, std.math.maxInt(u64)),
                .SDL => {
                    const shift: u6 = @intCast((paddr & 7) * 8);
                    const output = value >> shift;
                    const mask = @as(u64, std.math.maxInt(u64)) >> shift;
                    core.writeDoubleWord(paddr & ~@as(u32, 7), output, mask);
                },
                .SDR => {
                    const shift: u6 = @intCast((paddr & 7 ^ 7) * 8);
                    const output = value << shift;
                    const mask = @as(u64, std.math.maxInt(u64)) << shift;
                    core.writeDoubleWord(paddr & ~@as(u32, 7), output, mask);
                },
                .SC => {
                    if (core.ll_bit) {
                        core.writeWord(paddr, @truncate(value), std.math.maxInt(u32));
                    }

                    core.set(args.rt, @intFromBool(core.ll_bit));
                },
                .SCD => {
                    if (core.ll_bit) {
                        core.writeDoubleWord(paddr, value, std.math.maxInt(u64));
                    }

                    core.set(args.rt, @intFromBool(core.ll_bit));
                },
            }
        }
    }.instr;
}

pub fn cache(core: *Core, word: u32) void {
    _ = word;
    fw.log.trace("{X:08}: CACHE", .{core.pc});
    // TODO
}
