const std = @import("std");
const Core = @import("../Mos6502.zig");

pub const Mode = enum {
    const Self = @This();

    immediate,
    absolute,

    pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        _ = try writer.write(switch (self) {
            .immediate => "#const",
            .absolute => "addr",
        });
    }

    pub fn resolve(
        comptime self: Self,
        comptime iface: Core.Interface,
        core: *Core,
        write: bool,
    ) u16 {
        _ = write;

        return switch (comptime self) {
            .immediate => blk: {
                const address = core.pc;
                core.pc +%= 1;
                break :blk address;
            },
            .absolute => blk: {
                const lo = core.next(iface);
                const hi = core.next(iface);
                break :blk (@as(u16, hi) << 8) | lo;
            },
        };
    }
};
