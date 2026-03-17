const std = @import("std");
const Core = @import("../Mos6502.zig");

pub const Mode = enum {
    const Self = @This();

    immediate,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        _ = try writer.write(switch (self) {
            .immediate => "#const",
        });
    }

    pub fn resolve(self: Self, comptime iface: Core.Interface, core: *Core, write: bool) u16 {
        _ = iface;
        _ = write;

        return switch (self) {
            .immediate => blk: {
                const address = core.pc;
                core.pc +%= 1;
                break :blk address;
            },
        };
    }
};
