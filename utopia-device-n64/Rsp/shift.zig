const fw = @import("framework");
const Core = @import("./Core.zig");

pub const ShiftOp = enum {
    SLL,
    SRL,
    SRA,

    fn apply(comptime op: @This(), value: u32, shift: u5) u32 {
        return switch (comptime op) {
            .SLL => value << shift,
            .SRL => value >> shift,
            .SRA => @bitCast(fw.num.signed(value) >> shift),
        };
    }
};

pub fn fixed(comptime op: ShiftOp) Core.Instruction {
    return struct {
        fn instr(core: *Core, word: u32) void {
            const args: Core.RType = @bitCast(word);

            fw.log.trace("{X:03}: {t} {t}, {t}, {d}", .{
                core.pc,
                op,
                args.rd,
                args.rt,
                args.sa,
            });

            core.set(args.rd, op.apply(core.get(args.rt), args.sa));
        }
    }.instr;
}

pub fn variable(comptime op: ShiftOp) Core.Instruction {
    return struct {
        fn instr(core: *Core, word: u32) void {
            const args: Core.RType = @bitCast(word);

            fw.log.trace("{X:03}: {t}V {t}, {t}, {t}", .{
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
