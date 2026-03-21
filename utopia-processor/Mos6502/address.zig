const std = @import("std");
const Core = @import("../Mos6502.zig");

pub const Mode = enum {
    const Self = @This();

    immediate,
    absolute,
    absolute_x,
    absolute_y,
    zero_page,
    zero_page_x,
    zero_page_y,
    zero_page_x_indirect,
    zero_page_indirect_y,

    pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        _ = try writer.write(switch (self) {
            .immediate => "#const",
            .absolute => "addr",
            .absolute_x => "addr,X",
            .absolute_y => "addr,Y",
            .zero_page => "zp",
            .zero_page_x => "zp,X",
            .zero_page_y => "zp,Y",
            .zero_page_x_indirect => "(zp,X)",
            .zero_page_indirect_y => "(zp),Y",
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
            .absolute_x => indexAbsolute(iface, core, getAbsolute(iface, core), core.x, write),
            .absolute_y => indexAbsolute(iface, core, getAbsolute(iface, core), core.y, write),
            .zero_page => core.next(iface),
            .zero_page_x => indexZeroPage(iface, core, core.next(iface), core.x),
            .zero_page_y => indexZeroPage(iface, core, core.next(iface), core.y),
            .zero_page_x_indirect => blk: {
                const direct = indexZeroPage(iface, core, core.next(iface), core.x);
                break :blk getIndirect(iface, core, direct);
            },
            .zero_page_indirect_y => blk: {
                const indirect = getIndirect(iface, core, core.next(iface));
                break :blk indexAbsolute(iface, core, indirect, core.y, write);
            },
        };
    }
};

fn getAbsolute(iface: Core.Interface, core: *Core) u16 {
    const lo = core.next(iface);
    const hi = core.next(iface);
    return (@as(u16, hi) << 8) | lo;
}

fn getIndirect(iface: Core.Interface, core: *Core, direct: u8) u16 {
    const lo = core.read(iface, direct);
    const hi = core.read(iface, direct +% 1);
    return (@as(u16, hi) << 8) | lo;
}

fn indexAbsolute(iface: Core.Interface, core: *Core, base: u16, index: u8, write: bool) u16 {
    const result = base +% index;

    if (write or (result & 0xff00) != (base & 0xff00)) {
        _ = core.read(iface, (base & 0xff00) | (result & 0xff));
    }

    return result;
}

fn indexZeroPage(iface: Core.Interface, core: *Core, base: u8, index: u8) u8 {
    _ = core.read(iface, base);
    return base +% index;
}
