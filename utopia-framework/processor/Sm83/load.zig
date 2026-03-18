const fw = @import("framework");
const Core = @import("../Sm83.zig");
const address = @import("./address.zig");

pub fn ld(
    comptime dst: address.Mode8,
    comptime src: address.Mode8,
    comptime iface: Core.Interface,
    core: *Core,
) void {
    fw.log.trace("LD {f}, {f}", .{ dst, src });
    dst.write(iface, core, src.read(iface, core));
}

pub fn ld16(comptime dst: address.Mode16, comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("LD {f}, u16", .{dst});
    dst.write(core, core.nextWord(iface));
}

pub fn pop(comptime dst: address.Mode16, comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("POP {f}", .{dst});
    dst.write(core, core.popWord(iface));
}

pub fn push(comptime src: address.Mode16, comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("PUSH {f}", .{src});
    core.idle(iface);
    core.pushWord(iface, src.read(core));
}
