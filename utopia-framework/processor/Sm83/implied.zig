const fw = @import("framework");
const Core = @import("../Sm83.zig");

pub fn nop(comptime iface: Core.Interface, core: *Core) void {
    _ = iface;
    _ = core;
    fw.log.trace("NOP", .{});
}
