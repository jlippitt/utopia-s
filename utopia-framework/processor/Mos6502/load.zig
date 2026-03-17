const fw = @import("framework");
const Core = @import("../Mos6502.zig");
const AddressMode = @import("./address.zig").Mode;

const LoadOp = enum {
    LDA,
    LDX,
    LDY,
};

pub fn load(
    comptime op: LoadOp,
    comptime mode: AddressMode,
    comptime iface: Core.Interface,
    core: *Core,
) void {
    fw.log.trace("{t} {f}", .{ op, mode });
    const addr = mode.resolve(iface, core, false);
    core.poll();
    const value = core.read(iface, addr);

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
    }
}
