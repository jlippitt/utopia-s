const fw = @import("framework");
const Core = @import("../Mos6502.zig");
const AddressMode = @import("./address.zig").Mode;

pub const LoadOp = enum {
    LDA,
    LDX,
    LDY,
    CMP,
    CPX,
    CPY,
};

pub fn load(
    comptime op: LoadOp,
    comptime mode: AddressMode,
    comptime iface: Core.Interface,
    core: *Core,
) void {
    fw.log.trace("{t} {f}", .{ op, mode });
    const address = mode.resolve(iface, core, false);
    core.poll();
    const value = core.read(iface, address);

    switch (comptime op) {
        .LDA => {
            core.a = value;
            core.setNz(core.a);
        },
        .LDX => {
            core.x = value;
            core.setNz(core.x);
        },
        .LDY => {
            core.y = value;
            core.setNz(core.y);
        },
        .CMP => compare(core, core.a, value),
        .CPX => compare(core, core.x, value),
        .CPY => compare(core, core.y, value),
    }
}

fn compare(core: *Core, lhs: u8, rhs: u8) void {
    const result, const overflow = @subWithOverflow(lhs, rhs);
    core.setNz(result);
    core.flags.c = overflow == 0;
}
