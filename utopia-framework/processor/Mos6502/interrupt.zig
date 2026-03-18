const fw = @import("framework");
const Core = @import("../Mos6502.zig");

const nmi_vector: u16 = 0xfffa;
const reset_vector: u16 = 0xfffc;
const irq_vector: u16 = 0xfffe;

pub fn reset(comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("RESET", .{});
    _ = core.read(iface, core.pc);

    inline for (0..3) |_| {
        _ = core.read(iface, Core.stack_page | core.s);
        core.s -%= 1;
    }

    jumpToVector(iface, core, reset_vector);
}

pub fn brk(comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("BRK #const", .{});
    _ = core.next(iface);
    pushState(iface, core, 0xff);
    jumpToVector(iface, core, irq_vector);
}

pub fn rti(comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("RTI", .{});
    _ = core.read(iface, core.pc);
    _ = core.read(iface, Core.stack_page | core.s);
    core.flags = @bitCast(core.pull(iface) | 0x30);
    const lo = core.pull(iface);
    core.poll();
    const hi = core.pull(iface);
    core.pc = (@as(u16, hi) << 8) | lo;
}

fn pushState(comptime iface: Core.Interface, core: *Core, flag_mask: u8) void {
    core.push(iface, @truncate(core.pc >> 8));
    core.push(iface, @truncate(core.pc));
    core.push(iface, @as(u8, @bitCast(core.flags)) & flag_mask);
}

fn jumpToVector(comptime iface: Core.Interface, core: *Core, vector: u16) void {
    const lo = core.read(iface, vector);
    const hi = core.read(iface, vector +% 1);
    core.pc = (@as(u16, hi) << 8) | lo;
    core.flags.i = true;
}
