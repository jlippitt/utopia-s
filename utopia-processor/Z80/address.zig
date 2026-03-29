const std = @import("std");
const Core = @import("../Z80.zig");

pub const Mode8 = enum {
    const Self = @This();

    A,
    B,
    C,
    D,
    E,
    H,
    L,
    immediate,
    absolute,
    BC_indirect,
    DE_indirect,
    HL_indirect,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.writeAll(switch (self) {
            .immediate => "u8",
            .absolute => "(u16)",
            .BC_indirect => "(BC)",
            .DE_indirect => "(DE)",
            .HL_indirect => "(HL)",
            else => @tagName(self),
        });
    }

    pub fn read(comptime self: Self, iface: Core.Interface, core: *Core) u8 {
        return switch (comptime self) {
            .A => core.a,
            .B => @truncate(core.bc >> 8),
            .C => @truncate(core.bc),
            .D => @truncate(core.de >> 8),
            .E => @truncate(core.de),
            .H => @truncate(core.hl >> 8),
            .L => @truncate(core.hl),
            .immediate => core.nextByte(iface),
            .absolute => core.read(iface, core.nextWord(iface)),
            .BC_indirect => core.read(iface, core.bc),
            .DE_indirect => core.read(iface, core.de),
            .HL_indirect => core.read(iface, core.hl),
        };
    }

    pub fn write(comptime self: Self, iface: Core.Interface, core: *Core, value: u8) void {
        return switch (comptime self) {
            .A => core.a = value,
            .B => core.bc = (core.bc & 0xff) | (@as(u16, value) << 8),
            .C => core.bc = (core.bc & 0xff00) | @as(u16, value),
            .D => core.de = (core.de & 0xff) | (@as(u16, value) << 8),
            .E => core.de = (core.de & 0xff00) | @as(u16, value),
            .H => core.hl = (core.hl & 0xff) | (@as(u16, value) << 8),
            .L => core.hl = (core.hl & 0xff00) | @as(u16, value),
            .immediate => @compileError("Cannot write to immediate address"),
            .absolute => core.write(iface, core.nextWord(iface), value),
            .BC_indirect => core.write(iface, core.bc, value),
            .DE_indirect => core.write(iface, core.de, value),
            .HL_indirect => core.write(iface, core.hl, value),
        };
    }
};

pub const Mode16 = enum {
    const Self = @This();

    AF,
    BC,
    DE,
    HL,
    SP,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.writeAll(@tagName(self));
    }

    pub fn read(comptime self: Self, core: *Core) u16 {
        return switch (comptime self) {
            .AF => (@as(u16, core.a) << 8) | @as(u8, @bitCast(core.flags)),
            .BC => core.bc,
            .DE => core.de,
            .HL => core.hl,
            .SP => core.sp,
        };
    }

    pub fn write(comptime self: Self, core: *Core, value: u16) void {
        switch (comptime self) {
            .AF => {
                core.a = @truncate(value >> 8);
                core.flags = @bitCast(@as(u8, @truncate(value)) & 0xf0);
            },
            .BC => core.bc = value,
            .DE => core.de = value,
            .HL => core.hl = value,
            .SP => core.sp = value,
        }
    }
};
