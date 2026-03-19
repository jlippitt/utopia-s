const fw = @import("framework");
const Core = @import("../Sm83.zig");

const Condition = enum {
    NZ,
    Z,
    NC,
    C,

    fn apply(comptime cond: @This(), flags: *Core.Flags) bool {
        return switch (comptime cond) {
            .NZ => !flags.z,
            .Z => flags.z,
            .NC => !flags.c,
            .C => flags.c,
        };
    }
};

pub fn jr(comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("JR i8", .{});
    const offset = core.nextByte(iface);
    core.idle(iface);
    core.pc +%= fw.num.signExtend(u16, offset);
}

pub fn jrConditional(comptime cond: Condition, comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("JR {t}, i8", .{cond});
    const offset = core.nextByte(iface);

    if (cond.apply(&core.flags)) {
        fw.log.trace("  Branch taken", .{});
        core.idle(iface);
        core.pc +%= fw.num.signExtend(u16, offset);
    } else {
        fw.log.trace("  Branch not taken", .{});
    }
}

pub fn jp(comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("JP u16", .{});
    const target = core.nextWord(iface);
    core.idle(iface);
    core.pc = target;
}

pub fn jpHl(comptime iface: Core.Interface, core: *Core) void {
    _ = iface;
    fw.log.trace("JP HL", .{});
    core.pc = core.hl;
}

pub fn jpConditional(comptime cond: Condition, comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("JP {t}, u16", .{cond});
    const target = core.nextWord(iface);

    if (cond.apply(&core.flags)) {
        fw.log.trace("  Branch taken", .{});
        core.idle(iface);
        core.pc = target;
    } else {
        fw.log.trace("  Branch not taken", .{});
    }
}

pub fn call(comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("CALL u16", .{});
    const target = core.nextWord(iface);
    core.idle(iface);
    core.pushWord(iface, core.pc);
    core.pc = target;
}

pub fn callConditional(comptime cond: Condition, comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("CALL {t}, u16", .{cond});
    const target = core.nextWord(iface);

    if (cond.apply(&core.flags)) {
        fw.log.trace("  Branch taken", .{});
        core.idle(iface);
        core.pushWord(iface, core.pc);
        core.pc = target;
    } else {
        fw.log.trace("  Branch not taken", .{});
    }
}

pub fn ret(comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("RET", .{});
    core.pc = core.popWord(iface);
    core.idle(iface);
}

pub fn retConditional(comptime cond: Condition, comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("RET {t}", .{cond});
    core.idle(iface);

    if (cond.apply(&core.flags)) {
        fw.log.trace("  Branch taken", .{});
        core.pc = core.popWord(iface);
        core.idle(iface);
    } else {
        fw.log.trace("  Branch not taken", .{});
    }
}
