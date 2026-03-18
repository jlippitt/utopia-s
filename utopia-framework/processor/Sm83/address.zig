const std = @import("std");
const Core = @import("../Sm83.zig");

pub const Mode8 = enum {
    const Self = @This();

    A,
    B,
    C,
    D,
    E,
    H,
    L,
    HL_indirect,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.writeAll(switch (self) {
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
            .HL_indirect => core.read(iface, core.hl),
        };
    }
};

pub const Mode16 = enum {
    const Self = @This();

    BC,
    DE,
    HL,
    SP,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.writeAll(@tagName(self));
    }

    pub fn write(comptime self: Self, core: *Core, value: u16) void {
        switch (comptime self) {
            .BC => core.bc = value,
            .DE => core.de = value,
            .HL => core.hl = value,
            .SP => core.sp = value,
        }
    }
};
