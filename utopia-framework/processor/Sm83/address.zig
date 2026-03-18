const std = @import("std");
const Core = @import("../Sm83.zig");

pub const Mode16 = enum {
    const Self = @This();

    BC,
    DE,
    HL,
    SP,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("{t}", .{self});
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
