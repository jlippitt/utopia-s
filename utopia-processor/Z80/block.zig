const fw = @import("framework");
const Core = @import("../Z80.zig");

const OutOp = enum {
    const Self = @This();

    OUTI,
    OUTD,
    OTIR,
    OTDR,

    fn decrement(self: Self) bool {
        return self == .OUTD or self == .OTDR;
    }

    fn repeat(self: Self) bool {
        return self == .OTIR or self == .OTDR;
    }
};

pub fn out(comptime op: OutOp, comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("{t}", .{op});

    iface.idle(core, 1);
    const b: u8 = @truncate(core.bc >> 8);
    core.bc = (core.bc & 0xff) | (@as(u16, b) << 8);

    const value = core.read(iface, core.hl);

    if (comptime op.decrement()) {
        core.hl -%= 1;
    } else {
        core.hl +%= 1;
    }

    core.writeIo(iface, core.bc, value);

    if ((comptime op.repeat()) and b != 0) {
        core.idle(iface, 5);
        core.pc -%= 2;
    }
}
