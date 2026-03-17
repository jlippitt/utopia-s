const fw = @import("framework");
const Core = @import("../Mos6502.zig");
const AddressMode = @import("./address.zig").Mode;

const StoreOp = enum {
    STA,
    STX,
    STY,
};

pub fn store(
    comptime op: StoreOp,
    comptime mode: AddressMode,
    comptime iface: Core.Interface,
    core: *Core,
) void {
    fw.log.trace("{t} {f}", .{ op, mode });
    const address = mode.resolve(iface, core, false);
    core.poll();

    const value = switch (comptime op) {
        .STA => core.a,
        .STX => core.x,
        .STY => core.y,
    };

    core.write(iface, address, value);
}
