const fw = @import("framework");
const Core = @import("../Sm83.zig");
const address = @import("./address.zig");

pub fn ld16(comptime dst: address.Mode16, comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("LD {f}, u16", .{dst});
    dst.write(core, core.nextWord(iface));
}
