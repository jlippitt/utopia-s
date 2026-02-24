const fw = @import("framework");
const Core = @import("../Cpu.zig");

pub fn lui(core: *Core, word: u32) void {
    const args: Core.IType = @bitCast(word);
    fw.log.trace("{X:08}: LUI {t}, 0x{X:04}", .{ core.pc, args.rt, args.imm });
    const result = fw.num.signExtend(u64, @as(u32, args.imm) << 16);
    core.set(args.rt, result);
}
