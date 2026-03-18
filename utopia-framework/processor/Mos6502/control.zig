const fw = @import("framework");
const Core = @import("../Mos6502.zig");

pub const BranchOp = enum {
    BPL,
    BMI,
    BVC,
    BVS,
    BCC,
    BCS,
    BNE,
    BEQ,
};

pub fn branch(comptime op: BranchOp, comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("{t} nearlabel", .{op});
    core.poll();
    const offset = core.next(iface);

    const condition = switch (comptime op) {
        .BPL => !core.flags.n,
        .BMI => core.flags.n,
        .BVC => !core.flags.v,
        .BVS => core.flags.v,
        .BCC => !core.flags.c,
        .BCS => core.flags.c,
        .BNE => !core.flags.z,
        .BEQ => core.flags.z,
    };

    if (condition) {
        fw.log.trace("  Branch taken", .{});
        _ = core.read(iface, core.pc);

        const target = core.pc +% fw.num.signExtend(u16, offset);

        if ((target & 0xff00) != (core.pc & 0xff00)) {
            core.poll();
            _ = core.read(iface, (core.pc & 0xff00) | (target & 0xff));
        }

        core.pc = target;
    } else {
        fw.log.trace("  Branch not taken", .{});
    }
}
