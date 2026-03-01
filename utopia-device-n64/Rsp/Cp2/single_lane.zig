const std = @import("std");
const fw = @import("framework");
const Core = @import("../Core.zig");
const Cp2 = @import("../Cp2.zig");

const Args = packed struct(u32) {
    funct: u6,
    vd: Cp2.Register,
    vd_el: u5,
    vt: Cp2.Register,
    vt_el: u4,
    __: u1,
    opcode: u6,
};

pub fn vmov(core: *Core, word: u32) void {
    const args: Args = @bitCast(word);

    fw.log.trace("{X:03}: VMOV {t}[E:{d}], {t}[E:{d}]", .{
        core.pc,
        args.vd,
        args.vd_el,
        args.vt,
        args.vt_el,
    });

    core.cp2.setAccLow(core.cp2.broadcast(args.vt, args.vt_el));

    // Weird lane shenanigans that only occur on VMOV
    const vt_lane = switch (args.vt_el) {
        0...1 => args.vd_el & 7,
        2...3 => (args.vd_el & 6) | (args.vt_el & 1),
        4...7 => (args.vd_el & 4) | (args.vt_el & 3),
        else => args.vt_el & 7,
    };

    const vd_lane = args.vd_el & 7;

    core.cp2.setLane(args.vd, vd_lane, core.cp2.getLane(args.vt, vt_lane));
}
