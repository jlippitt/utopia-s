const std = @import("std");
const fw = @import("framework");
const op_table = @import("./Z80/op_table.zig");

pub const Flags = packed struct(u8) {
    c: bool = true,
    n: bool = true,
    p: bool = true,
    x: bool = true,
    h: bool = true,
    y: bool = true,
    z: bool = true,
    s: bool = true,
};

pub const Interface = struct {
    fetch: fn (self: *Self, address: u16) u8,
};

pub const Instruction = fn (core: *Self) void;

const Self = @This();

pc: u16 = 0,
a: u8 = 0xff,
flags: Flags = .{},
bc: u16 = undefined,
de: u16 = undefined,
hl: u16 = undefined,
sp: u16 = 0xffff,
ix: u16 = undefined,
iy: u16 = undefined,
af_alt: u16 = undefined,
bc_alt: u16 = undefined,
de_alt: u16 = undefined,
hl_alt: u16 = undefined,
internal: u16 = undefined,
i: u8 = undefined,
r: u8 = undefined,
im: u2 = 0,
iff1: bool = false,
iff2: bool = false,
iff_delay: bool = false,

pub fn init() Self {
    return .{};
}

pub fn format(self: *const Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("A={X:02} BC={X:04} DE={X:04} HL={X:04} IX={X:04} IY={X:04} SP={X:04} PC={X:04} F={c}{c}{c}{c}", .{
        self.a,
        self.bc,
        self.de,
        self.hl,
        self.ix,
        self.iy,
        self.sp,
        self.pc,
        @as(u8, if (self.flags.z) 'Z' else '-'),
        @as(u8, if (self.flags.n) 'N' else '-'),
        @as(u8, if (self.flags.h) 'H' else '-'),
        @as(u8, if (self.flags.c) 'C' else '-'),
    });
}

pub fn step(self: *Self, comptime iface: Interface) void {
    // TODO: Interrupt check

    self.iff_delay = false;

    self.decode(iface)(self);
}

pub fn fetch(self: *Self, comptime iface: Interface) u8 {
    const value = iface.fetch(self, self.pc);
    fw.log.trace("  {X:04} => {X:02}", .{ self.pc, value });
    self.pc +%= 1;
    return value;
}

// pub fn idle(self: *Self, comptime iface: Interface) void {
//     fw.log.trace("  IO", .{});
//     iface.idle(self);
// }

// pub fn read(self: *Self, comptime iface: Interface, address: u16) u8 {
//     const value = iface.read(self, address);
//     fw.log.trace("  {X:04} => {X:02}", .{ address, value });
//     return value;
// }

// pub fn write(self: *Self, comptime iface: Interface, address: u16, value: u8) void {
//     fw.log.trace("  {X:04} <= {X:02}", .{ address, value });
//     iface.write(self, address, value);
// }

// pub fn readIo(self: *Self, comptime iface: Interface, address: u8) u8 {
//     const value = iface.readIo(self, address);
//     fw.log.trace("  FF{X:02} => {X:02}", .{ address, value });
//     return value;
// }

// pub fn writeIo(self: *Self, comptime iface: Interface, address: u8, value: u8) void {
//     fw.log.trace("  FF{X:02} <= {X:02}", .{ address, value });
//     iface.writeIo(self, address, value);
// }

// pub fn nextByte(self: *Self, comptime iface: Interface) u8 {
//     const value = self.read(iface, self.pc);
//     self.pc +%= 1;
//     return value;
// }

// pub fn nextWord(self: *Self, comptime iface: Interface) u16 {
//     const lo = self.nextByte(iface);
//     const hi = self.nextByte(iface);
//     return (@as(u16, hi) << 8) | lo;
// }

// pub fn popWord(self: *Self, comptime iface: Interface) u16 {
//     const lo = self.read(iface, self.sp);
//     self.sp +%= 1;
//     const hi = self.read(iface, self.sp);
//     self.sp +%= 1;
//     return (@as(u16, hi) << 8) | lo;
// }

// pub fn pushWord(self: *Self, comptime iface: Interface, value: u16) void {
//     self.sp -%= 1;
//     self.write(iface, self.sp, @truncate(value >> 8));
//     self.sp -%= 1;
//     self.write(iface, self.sp, @truncate(value));
// }

fn decode(self: *Self, comptime iface: Interface) *const Instruction {
    @setEvalBranchQuota(2000);

    const opcode = self.fetch(iface);

    return switch (opcode) {
        0xcb => (comptime op_table.cb(iface))[self.fetch(iface)],
        0xed => (comptime op_table.ed(iface))[self.fetch(iface)],
        else => (comptime op_table.main(iface))[opcode],
    };
}
