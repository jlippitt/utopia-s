const fw = @import("framework");
const Core = @import("../Mos6502.zig");
const AddressMode = @import("./address.zig").Mode;

pub const ModifyOp = enum {
    DEC,
    INC,
};

pub fn memory(
    comptime op: ModifyOp,
    comptime mode: AddressMode,
    comptime iface: Core.Interface,
    core: *Core,
) void {
    fw.log.trace("{t} {f}", .{ op, mode });
    const address = mode.resolve(iface, core, true);
    const value = core.read(iface, address);
    core.write(iface, address, value);

    const result = switch (comptime op) {
        .DEC => value -% 1,
        .INC => value +% 1,
    };

    core.setNz(result);
    core.poll();
    core.write(iface, address, result);
}
