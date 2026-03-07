const std = @import("std");
const fw = @import("framework");
const Core = @import("./Core.zig");

pub const LoadOp = enum {
    LB,
    LBU,
    LH,
    LHU,
    LW,
    LWU,
};

pub fn load(comptime op: LoadOp) Core.Instruction {
    return struct {
        fn instr(core: *Core, word: u32) void {
            const args: Core.IType = @bitCast(word);
            const offset: u12 = @truncate(args.imm);

            fw.log.trace("{X:03}: {t} {t}, {d}({t})", .{
                core.pc,
                op,
                args.rt,
                fw.num.signed(offset),
                args.rs,
            });

            const address = @as(u12, @truncate(core.get(args.rs))) +% offset;

            core.set(args.rt, switch (comptime op) {
                .LB => fw.num.signExtend(u32, core.readData(u8, address)),
                .LBU => fw.num.zeroExtend(u32, core.readData(u8, address)),
                .LH => fw.num.signExtend(u32, core.readData(u16, address)),
                .LHU => fw.num.zeroExtend(u32, core.readData(u16, address)),
                .LW, .LWU => core.readData(u32, address),
            });
        }
    }.instr;
}

pub const StoreOp = enum {
    SB,
    SH,
    SW,
};

pub fn store(comptime op: StoreOp) Core.Instruction {
    return struct {
        fn instr(core: *Core, word: u32) void {
            const args: Core.IType = @bitCast(word);
            const offset: u12 = @truncate(args.imm);

            fw.log.trace("{X:03}: {t} {t}, {d}({t})", .{
                core.pc,
                op,
                args.rt,
                fw.num.signed(offset),
                args.rs,
            });

            const address = @as(u12, @truncate(core.get(args.rs))) +% offset;

            const value = core.get(args.rt);

            switch (comptime op) {
                .SB => core.writeData(u8, address, @truncate(value)),
                .SH => core.writeData(u16, address, @truncate(value)),
                .SW => core.writeData(u32, address, value),
            }
        }
    }.instr;
}
