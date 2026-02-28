const std = @import("std");
const fw = @import("framework");
const Core = @import("./Core.zig");
const memory = @import("./Cp2/memory.zig");

const Self = @This();

// zig fmt: off
pub const Register = enum(u5) {
    V00, V01, V02, V03, V04, V05, V06, V07,
    V08, V09, V10, V11, V12, V13, V14, V15,
    V16, V17, V18, V19, V20, V21, V22, V23,
    V24, V25, V26, V27, V28, V29, V30, V31,
};
// zig fmt: on

regs: [32]@Vector(8, u16) = @splat(@splat(0)),

pub fn init() Self {
    return .{};
}

pub fn get(self: *const Self, reg: Register) @Vector(8, u16) {
    return self.regs[@intFromEnum(reg)];
}

pub fn set(self: *Self, reg: Register, value: @Vector(8, u16)) void {
    self.regs[@intFromEnum(reg)] = value;
    fw.log.trace("  {t}: {any}", .{ reg, value });
}

pub fn getEl(self: *const Self, comptime T: type, reg: Register, el: u4) T {
    const bits = comptime @typeInfo(T).int.bits;
    const shift = @as(i32, 128) - (@as(i32, @intCast(el)) * 8) - bits;
    return @truncate(std.math.rotr(u128, @bitCast(self.get(reg)), shift));
}

pub fn setEl(self: *Self, comptime T: type, reg: Register, el: u4, value: T) void {
    const bits = comptime @typeInfo(T).int.bits;
    const shift = @as(i32, 128) - (@as(i32, @intCast(el)) * 8) - bits;
    var result: u128 = @bitCast(self.get(reg));
    result &= ~std.math.shl(u128, @as(u128, std.math.maxInt(T)), shift);
    result |= std.math.shl(u128, value, shift);
    self.set(reg, @bitCast(result));
}

pub fn cop2(core: *Core, word: u32) void {
    _ = core;

    const rs: u5 = @truncate(word >> 21);

    if (rs >= 0o20) {
        return switch (@as(u6, @truncate(word))) {
            else => |funct| fw.log.todo("RSP COP2 funct: {o:02}", .{funct}),
        };
    }

    switch (rs) {
        // 0o00 => mfc2(core, word),
        // 0o01 => dmfc2(core, word),
        // 0o04 => mtc2(core, word),
        // 0o05 => dmtc2(core, word),
        else => fw.log.todo("RSP COP2 rs: {o:02}", .{rs}),
    }
}

pub fn lwc2(core: *Core, word: u32) void {
    switch (@as(u5, @truncate(word >> 11))) {
        0o00 => memory.load(.BV, core, word),
        0o01 => memory.load(.SV, core, word),
        0o02 => memory.load(.LV, core, word),
        0o03 => memory.load(.DV, core, word),
        0o04 => memory.load(.QV, core, word),
        // 0o05 => memory.load(.RV, core, word),
        else => |rd| fw.log.todo("RSP LWC2 rd: {o:02}", .{rd}),
    }
}

pub fn swc2(core: *Core, word: u32) void {
    switch (@as(u5, @truncate(word >> 11))) {
        0o00 => memory.store(.BV, core, word),
        0o01 => memory.store(.SV, core, word),
        0o02 => memory.store(.LV, core, word),
        0o03 => memory.store(.DV, core, word),
        0o04 => memory.store(.QV, core, word),
        // 0o05 => memory.store(.RV, core, word),
        else => |rd| fw.log.todo("RSP SWC2 rd: {o:02}", .{rd}),
    }
}
