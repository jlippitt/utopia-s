const fw = @import("framework");
const Core = @import("../Sm83.zig");
const address = @import("./address.zig");

pub fn add(comptime src: address.Mode8, comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("ADD A, {f}", .{src});
    core.a = addWithCarry(core, src.read(iface, core), false);
}

pub fn adc(comptime src: address.Mode8, comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("ADC A, {f}", .{src});
    core.a = addWithCarry(core, src.read(iface, core), core.flags.c);
}

pub fn sub(comptime src: address.Mode8, comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("SUB A, {f}", .{src});
    core.a = subWithBorrow(core, src.read(iface, core), false);
}

pub fn sbc(comptime src: address.Mode8, comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("SBC A, {f}", .{src});
    core.a = subWithBorrow(core, src.read(iface, core), core.flags.c);
}

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

pub fn cp(comptime src: address.Mode8, comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("CP A, {f}", .{src});
    _ = subWithBorrow(core, src.read(iface, core), false);
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

pub fn add16(comptime src: address.Mode16, comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("ADD HL, {f}", .{src});
    core.idle(iface);
    const lhs = core.hl;
    const rhs = src.read(core);
    const result = lhs +% rhs;
    const carries = lhs ^ rhs ^ result;
    const overflow = (lhs ^ result) & (rhs ^ result);
    core.hl = result;
    core.flags.n = false;
    core.flags.h = fw.num.bit(carries, 12);
    core.flags.c = fw.num.bit((carries ^ overflow), 15);
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

fn addWithCarry(core: *Core, rhs: u8, carry: bool) u8 {
    const lhs = core.a;
    const result = lhs +% rhs +% @intFromBool(carry);
    const carries = lhs ^ rhs ^ result;
    const overflow = (lhs ^ result) & (rhs ^ result);
    core.flags.z = result == 0;
    core.flags.n = false;
    core.flags.h = fw.num.bit(carries, 4);
    core.flags.c = fw.num.bit((carries ^ overflow), 7);
    return result;
}

fn subWithBorrow(core: *Core, rhs: u8, carry: bool) u8 {
    const lhs = core.a;
    const result = lhs -% rhs -% @intFromBool(carry);
    const carries = lhs ^ rhs ^ result;
    const overflow = (lhs ^ result) & (lhs ^ rhs);
    core.flags.z = result == 0;
    core.flags.n = true;
    core.flags.h = fw.num.bit(carries, 4);
    core.flags.c = fw.num.bit((carries ^ overflow), 7);
    return result;
}
