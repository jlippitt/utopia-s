const fw = @import("framework");
const Core = @import("../Sm83.zig");
const address = @import("./address.zig");

pub fn rlc(comptime mode: address.Mode8, comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("RLC {f}", .{mode});
    const value = mode.read(iface, core);
    core.flags.c = fw.num.bit(value, 7);
    const result = (value << 1) | (value >> 7);
    mode.write(iface, core, result);
    core.flags.z = result == 0;
    core.flags.n = false;
    core.flags.h = false;
}

pub fn rrc(comptime mode: address.Mode8, comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("RRC {f}", .{mode});
    const value = mode.read(iface, core);
    core.flags.c = fw.num.bit(value, 0);
    const result = (value >> 1) | (value << 7);
    mode.write(iface, core, result);
    core.flags.z = result == 0;
    core.flags.n = false;
    core.flags.h = false;
}

pub fn rl(comptime mode: address.Mode8, comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("RL {f}", .{mode});
    const value = mode.read(iface, core);
    const carry: u8 = @intFromBool(core.flags.c);
    core.flags.c = fw.num.bit(value, 7);
    const result = (value << 1) | carry;
    mode.write(iface, core, result);
    core.flags.z = result == 0;
    core.flags.n = false;
    core.flags.h = false;
}

pub fn rr(comptime mode: address.Mode8, comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("RR {f}", .{mode});
    const value = mode.read(iface, core);
    const carry: u8 = @intFromBool(core.flags.c);
    core.flags.c = fw.num.bit(value, 0);
    const result = (value >> 1) | (carry << 7);
    mode.write(iface, core, result);
    core.flags.z = result == 0;
    core.flags.n = false;
    core.flags.h = false;
}

pub fn sla(comptime mode: address.Mode8, comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("SLA {f}", .{mode});
    const value = mode.read(iface, core);
    core.flags.c = fw.num.bit(value, 7);
    const result = value << 1;
    mode.write(iface, core, result);
    core.flags.z = result == 0;
    core.flags.n = false;
    core.flags.h = false;
}

pub fn sra(comptime mode: address.Mode8, comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("SRA {f}", .{mode});
    const value = mode.read(iface, core);
    core.flags.c = fw.num.bit(value, 0);
    const result = (value & 0x80) | (value >> 1);
    mode.write(iface, core, result);
    core.flags.z = result == 0;
    core.flags.n = false;
    core.flags.h = false;
}

pub fn swap(comptime mode: address.Mode8, comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("SWAP {f}", .{mode});
    const value = mode.read(iface, core);
    const result = (value << 4) | (value >> 4);
    mode.write(iface, core, result);
    core.flags.z = result == 0;
    core.flags.n = false;
    core.flags.h = false;
    core.flags.c = false;
}

pub fn srl(comptime mode: address.Mode8, comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("SRL {f}", .{mode});
    const value = mode.read(iface, core);
    core.flags.c = fw.num.bit(value, 0);
    const result = value >> 1;
    mode.write(iface, core, result);
    core.flags.z = result == 0;
    core.flags.n = false;
    core.flags.h = false;
}

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
