const fw = @import("framework");
const Core = @import("../Mos6502.zig");

const ImpliedOp = enum {
    CLC,
    SEC,
    CLI,
    SEI,
    CLV,
    CLD,
    SED,
    TAX,
    TXA,
    TAY,
    TYA,
    TSX,
    TXS,
    INX,
    DEX,
    INY,
    DEY,
};

pub fn implied(comptime op: ImpliedOp, comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("{t}", .{op});
    core.poll();
    _ = core.read(iface, core.pc);

    switch (comptime op) {
        .CLC => core.flags.c = false,
        .SEC => core.flags.c = true,
        .CLI => core.flags.i = false,
        .SEI => core.flags.i = true,
        .CLV => core.flags.v = false,
        .CLD => core.flags.d = false,
        .SED => core.flags.d = true,
        .TAX => {
            core.x = core.a;
            core.setNz(core.x);
        },
        .TXA => {
            core.a = core.x;
            core.setNz(core.a);
        },
        .TAY => {
            core.y = core.a;
            core.setNz(core.y);
        },
        .TYA => {
            core.a = core.y;
            core.setNz(core.a);
        },
        .TSX => {
            core.x = core.s;
            core.setNz(core.x);
        },
        .TXS => core.s = core.x,
        .INX => {
            core.x +%= 1;
            core.setNz(core.x);
        },
        .DEX => {
            core.x -%= 1;
            core.setNz(core.x);
        },
        .INY => {
            core.y +%= 1;
            core.setNz(core.y);
        },
        .DEY => {
            core.y -%= 1;
            core.setNz(core.y);
        },
    }
}
