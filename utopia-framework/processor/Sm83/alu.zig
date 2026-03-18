const fw = @import("framework");
const Core = @import("../Sm83.zig");
const address = @import("./address.zig");

pub fn and_(comptime src: address.Mode8, comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("AND A, {f}", .{src});
    core.a &= src.read(iface, core);
    core.flags.z = core.a == 0;
    core.flags.n = false;
    core.flags.h = true;
    core.flags.c = false;
}

pub fn xor(comptime src: address.Mode8, comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("XOR A, {f}", .{src});
    core.a ^= src.read(iface, core);
    core.flags.z = core.a == 0;
    core.flags.n = false;
    core.flags.h = false;
    core.flags.c = false;
}

pub fn or_(comptime src: address.Mode8, comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("OR A, {f}", .{src});
    core.a |= src.read(iface, core);
    core.flags.z = core.a == 0;
    core.flags.n = false;
    core.flags.h = false;
    core.flags.c = false;
}
