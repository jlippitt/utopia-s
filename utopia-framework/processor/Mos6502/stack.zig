const fw = @import("framework");
const Core = @import("../Mos6502.zig");

pub fn php(comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("PHP", .{});
    _ = core.read(iface, core.pc);
    core.push(iface, @as(u8, @bitCast(core.flags)));
}

pub fn plp(comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("PLP", .{});
    _ = core.read(iface, core.pc);
    _ = core.read(iface, Core.stack_page | core.s);
    core.flags = @bitCast(core.pull(iface) | 0x30);
}

pub fn pha(comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("PHA", .{});
    _ = core.read(iface, core.pc);
    core.push(iface, core.a);
}

pub fn pla(comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("PLA", .{});
    _ = core.read(iface, core.pc);
    _ = core.read(iface, Core.stack_page | core.s);
    core.a = core.pull(iface);
    core.setNz(core.a);
}
