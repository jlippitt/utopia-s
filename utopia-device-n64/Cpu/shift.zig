const fw = @import("framework");
const Core = @import("../Cpu.zig");

pub const ShiftOp = enum {
    SLL,
    SRL,
    SRA,
    DSLL,
    DSRL,
    DSRA,

    fn apply(comptime op: @This(), value: u64, shift: u6) u64 {
        return switch (comptime op) {
            .SLL => fw.num.signExtend(u64, @as(u32, @truncate(value)) << @truncate(shift)),
            .SRL => fw.num.signExtend(u64, @as(u32, @truncate(value)) >> @truncate(shift)),
            .SRA => fw.num.signExtend(
                u64,
                @as(i32, @truncate(fw.num.signed(value) >> @as(u5, @truncate(shift)))),
            ),
            .DSLL => value << shift,
            .DSRL => value >> shift,
            .DSRA => @bitCast(fw.num.signed(value) >> shift),
        };
    }
};

pub fn fixed(comptime op: ShiftOp) Core.Instruction {
    return struct {
        fn instr(core: *Core, word: u32) void {
            const args: Core.RType = @bitCast(word);

            if ((comptime op == .SLL) and word == 0) {
                fw.log.trace("{X:08}: NOP", .{core.pc});

                if (core.busy_wait) {
                    @branchHint(.unlikely);
                    core.getDevice().clock.fastForward();
                }
            } else {
                fw.log.trace("{X:08}: {t} {t}, {t}, {d}", .{
                    core.pc,
                    op,
                    args.rd,
                    args.rt,
                    args.sa,
                });
            }

            core.set(args.rd, op.apply(core.get(args.rt), args.sa));
        }
    }.instr;
}

pub fn fixed32(comptime op: ShiftOp) Core.Instruction {
    return struct {
        fn instr(core: *Core, word: u32) void {
            const args: Core.RType = @bitCast(word);

            fw.log.trace("{X:08}: {t}32 {t}, {t}, {d}", .{
                core.pc,
                op,
                args.rd,
                args.rt,
                args.sa,
            });

            core.set(args.rd, op.apply(core.get(args.rt), @as(u6, args.sa) + 32));
        }
    }.instr;
}

pub fn variable(comptime op: ShiftOp) Core.Instruction {
    return struct {
        fn instr(core: *Core, word: u32) void {
            const args: Core.RType = @bitCast(word);

            fw.log.trace("{X:08}: {t}V {t}, {t}, {t}", .{
                core.pc,
                op,
                args.rd,
                args.rt,
                args.rs,
            });

            core.set(args.rd, op.apply(core.get(args.rt), @truncate(core.get(args.rs))));
        }
    }.instr;
}
