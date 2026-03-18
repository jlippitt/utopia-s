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

pub fn inc(comptime mode: address.Mode8, comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("INC {f}", .{mode});
    const value = mode.read(iface, core);
    const result = value +% 1;
    mode.write(iface, core, result);
    core.flags.z = result == 0;
    core.flags.n = false;
    core.flags.h = (result & 0x0f) == 0;
}

pub fn dec(comptime mode: address.Mode8, comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("DEC {f}", .{mode});
    const value = mode.read(iface, core);
    const result = value -% 1;
    mode.write(iface, core, result);
    core.flags.z = result == 0;
    core.flags.n = true;
    core.flags.h = (result & 0x0f) == 0x0f;
}

pub fn inc16(comptime mode: address.Mode16, comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("INC {f}", .{mode});
    core.idle(iface);
    const value = mode.read(core);
    const result = value +% 1;
    mode.write(core, result);
}

pub fn dec16(comptime mode: address.Mode16, comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("DEC {f}", .{mode});
    core.idle(iface);
    const value = mode.read(core);
    const result = value -% 1;
    mode.write(core, result);
}
