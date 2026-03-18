const std = @import("std");
const Core = @import("../Mos6502.zig");

pub const Mode = enum {
    const Self = @This();

    immediate,
    absolute,
    absolute_x,
    absolute_y,
    zero_page,

    pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        _ = try writer.write(switch (self) {
            .immediate => "#const",
            .absolute => "addr",
            .absolute_x => "addr,X",
            .absolute_y => "addr,Y",
            .zero_page => "zp",
        });
    }

    pub fn resolve(
        comptime self: Self,
        comptime iface: Core.Interface,
        core: *Core,
        write: bool,
    ) u16 {
        return switch (comptime self) {
            .immediate => blk: {
                const address = core.pc;
                core.pc +%= 1;
                break :blk address;
            },
            .absolute => getAbsolute(iface, core),
            .absolute_x => blk: {
                const base = getAbsolute(iface, core);
                break :blk indexAbsolute(iface, core, base, core.x, write);
            },
            .absolute_y => blk: {
                const base = getAbsolute(iface, core);
                break :blk indexAbsolute(iface, core, base, core.y, write);
            },
            .zero_page => core.next(iface),
        };
    }
};

fn getAbsolute(iface: Core.Interface, core: *Core) u16 {
    const lo = core.next(iface);
    const hi = core.next(iface);
    return (@as(u16, hi) << 8) | lo;
}

fn indexAbsolute(iface: Core.Interface, core: *Core, base: u16, index: u8, write: bool) u16 {
    const result = base +% index;

    if (write or (result & 0xff00) != (base & 0xff00)) {
        _ = core.read(iface, (base & 0xff00) | (result & 0xff));
    }

    return result;
}
