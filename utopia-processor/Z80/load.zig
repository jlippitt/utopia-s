const std = @import("std");
const fw = @import("framework");
const Core = @import("../Z80.zig");
const address = @import("./address.zig");

pub fn ld(
    comptime dst: address.Mode8,
    comptime src: address.Mode8,
    comptime iface: Core.Interface,
    core: *Core,
) void {
    fw.log.trace("LD {f}, {f}", .{ dst, src });
    dst.write(iface, core, src.read(iface, core));
}

pub fn ld16(comptime dst: address.Mode16, comptime iface: Core.Interface, core: *Core) void {
    fw.log.trace("LD {f}, u16", .{dst});
    dst.write(core, core.nextWord(iface));
}

// pub fn ldSpHl(comptime iface: Core.Interface, core: *Core) void {
//     fw.log.trace("LD SP, HL", .{});
//     core.idle(iface);
//     core.sp = core.hl;
// }

// pub fn ldAbsoluteSp(comptime iface: Core.Interface, core: *Core) void {
//     fw.log.trace("LD (u16), SP", .{});
//     const base = core.nextWord(iface);
//     core.write(iface, base, @truncate(core.sp));
//     core.write(iface, base +% 1, @truncate(core.sp >> 8));
// }

// pub fn pop(comptime dst: address.Mode16, comptime iface: Core.Interface, core: *Core) void {
//     fw.log.trace("POP {f}", .{dst});
//     dst.write(core, core.popWord(iface));
// }

// pub fn push(comptime src: address.Mode16, comptime iface: Core.Interface, core: *Core) void {
//     fw.log.trace("PUSH {f}", .{src});
//     core.idle(iface);
//     core.pushWord(iface, src.read(core));
// }

pub fn exx(comptime iface: Core.Interface, core: *Core) void {
    _ = iface;
    fw.log.trace("EXX", .{});
    std.mem.swap(u16, &core.bc, &core.bc_alt);
    std.mem.swap(u16, &core.de, &core.de_alt);
    std.mem.swap(u16, &core.hl, &core.hl_alt);
}
