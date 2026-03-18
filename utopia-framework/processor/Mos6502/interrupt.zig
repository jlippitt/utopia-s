const fw = @import("framework");
const Core = @import("../Mos6502.zig");

const reset_vector: u16 = 0xfffc;

pub fn reset(comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("RESET", .{});
    _ = core.read(iface, core.pc);

    inline for (0..3) |_| {
        _ = core.read(iface, Core.stack_page | core.s);
        core.s -%= 1;
    }

    const lo = core.read(iface, reset_vector);
    const hi = core.read(iface, reset_vector +% 1);
    core.pc = (@as(u16, hi) << 8) | lo;
    core.flags.i = true;
}

pub fn rti(comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("RTI", .{});
    _ = core.read(iface, core.pc);
    _ = core.read(iface, Core.stack_page | core.s);
    core.flags = @bitCast(core.pull(iface) & 0xcf);
    const lo = core.pull(iface);
    core.poll();
    const hi = core.pull(iface);
    core.pc = (@as(u16, hi) << 8) | lo;
}
