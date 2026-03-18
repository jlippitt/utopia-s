const fw = @import("framework");
const Core = @import("../Sm83.zig");
const address = @import("./address.zig");

pub fn bit(
    comptime index: u3,
    comptime mode: address.Mode8,
    comptime iface: Core.Interface,
    core: *Core,
) void {
    fw.log.trace("BIT {d}, {f}", .{ index, mode });
    const value = mode.read(iface, core);
    core.flags.z = !fw.num.bit(value, index);
    core.flags.n = false;
    core.flags.h = true;
}

pub fn res(
    comptime index: u3,
    comptime mode: address.Mode8,
    comptime iface: Core.Interface,
    core: *Core,
) void {
    fw.log.trace("RES {d}, {f}", .{ index, mode });
    const value = mode.read(iface, core);
    const result = value & ~(@as(u8, 1) << index);
    mode.write(iface, core, result);
}

pub fn set(
    comptime index: u3,
    comptime mode: address.Mode8,
    comptime iface: Core.Interface,
    core: *Core,
) void {
    fw.log.trace("SET {d}, {f}", .{ index, mode });
    const value = mode.read(iface, core);
    const result = value | (@as(u8, 1) << index);
    mode.write(iface, core, result);
}
