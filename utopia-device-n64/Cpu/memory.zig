const fw = @import("framework");
const Core = @import("../Cpu.zig");

pub const LoadOp = enum {
    LW,
    LWU,
};

pub fn load(comptime op: LoadOp, comptime bus: Core.Bus, core: *Core, word: u32) void {
    const args: Core.IType = @bitCast(word);
    const offset = fw.num.signExtend(u64, args.imm);

    fw.log.trace("{X:08}: {t} {t}, {d}({t})", .{ core.pc, op, args.rt, offset, args.rs });

    const vaddr = core.get(args.rs) +% offset;
    const paddr = core.mapAddress(@truncate(vaddr)) orelse return;

    core.set(args.rt, switch (comptime op) {
        .LW => fw.num.signExtend(u64, core.readWord(bus, paddr)),
        .LWU => fw.num.zeroExtend(u64, core.readWord(bus, paddr)),
    });
}
