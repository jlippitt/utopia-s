const fw = @import("framework");
const Core = @import("../Mos6502.zig");
const AddressMode = @import("./address.zig").Mode;

pub const ModifyOp = enum {
    ASL,
    ROL,
    LSR,
    ROR,
    DEC,
    INC,

    fn apply(comptime op: @This(), core: *Core, value: u8) u8 {
        const result = switch (comptime op) {
            .ASL => blk: {
                core.flags.c = fw.num.bit(value, 7);
                break :blk value << 1;
            },
            .ROL => blk: {
                const carry: u8 = @intFromBool(core.flags.c);
                core.flags.c = fw.num.bit(value, 7);
                break :blk (value << 1) | carry;
            },
            .LSR => blk: {
                core.flags.c = fw.num.bit(value, 0);
                break :blk value >> 1;
            },
            .ROR => blk: {
                const carry: u8 = @intFromBool(core.flags.c);
                core.flags.c = fw.num.bit(value, 0);
                break :blk (value >> 1) | (carry << 7);
            },
            .DEC => value -% 1,
            .INC => value +% 1,
        };

        core.setNz(result);

        return result;
    }
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
    const result = op.apply(core, value);
    core.poll();
    core.write(iface, address, result);
}

pub fn accumulator(
    comptime op: ModifyOp,
    comptime iface: Core.Interface,
    core: *Core,
) void {
    fw.log.trace("{t} A", .{op});
    core.poll();
    _ = core.read(iface, core.pc);
    core.a = op.apply(core, core.a);
}
