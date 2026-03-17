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
};

pub fn implied(comptime iface: Core.Interface, comptime op: ImpliedOp, core: *Core) void {
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
    }
}
