const fw = @import("framework");
const Core = @import("../Sm83.zig");

pub fn nop(comptime iface: Core.Interface, core: *Core) void {
    _ = iface;
    _ = core;
    fw.log.trace("NOP", .{});
}

pub fn di(comptime iface: Core.Interface, core: *Core) void {
    _ = iface;
    fw.log.trace("DI", .{});
    core.ime = false;
    core.ime_next = false;
}

pub fn ei(comptime iface: Core.Interface, core: *Core) void {
    _ = iface;
    fw.log.trace("EI", .{});
    core.ime_next = true;
}

pub fn scf(comptime iface: Core.Interface, core: *Core) void {
    _ = iface;
    fw.log.trace("SCF", .{});
    core.flags.n = false;
    core.flags.h = false;
    core.flags.c = true;
}

pub fn ccf(comptime iface: Core.Interface, core: *Core) void {
    _ = iface;
    fw.log.trace("CCF", .{});
    core.flags.n = false;
    core.flags.h = false;
    core.flags.c = !core.flags.c;
}
