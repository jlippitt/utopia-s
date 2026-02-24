const fw = @import("framework");
const Core = @import("../Cpu.zig");

pub const LogicOp = enum {
    AND,
    OR,
    XOR,
    NOR,

    fn apply(comptime op: @This(), lhs: u64, rhs: u64) u64 {
        return switch (comptime op) {
            .AND => lhs & rhs,
            .OR => lhs | rhs,
            .XOR => lhs ^ rhs,
            .NOR => !(lhs | rhs),
        };
    }
};

pub fn lui(core: *Core, word: u32) void {
    const args: Core.IType = @bitCast(word);
    fw.log.trace("{X:08}: LUI {t}, 0x{X:04}", .{ core.pc, args.rt, args.imm });
    core.set(args.rt, fw.num.signExtend(u64, @as(u32, args.imm) << 16));
}

pub fn iTypeLogic(comptime op: LogicOp, core: *Core, word: u32) void {
    const args: Core.IType = @bitCast(word);
    fw.log.trace("{X:08}: {t}I {t}, {t}, 0x{X:04}", .{ core.pc, op, args.rt, args.rs, args.imm });
    core.set(args.rt, op.apply(core.get(args.rs), args.imm));
}
