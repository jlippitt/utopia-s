const std = @import("std");
const fw = @import("framework");
const alu = @import("./Sm83/alu.zig");
const bit = @import("./Sm83/bit.zig");
const control = @import("./Sm83/control.zig");
const load = @import("./Sm83/load.zig");

pub const Flags = packed struct(u8) {
    __: u4 = 0,
    c: bool = false,
    h: bool = false,
    n: bool = false,
    z: bool = false,
};

pub const Interface = struct {
    idle: fn (self: *Self) void,
    read: fn (self: *Self, address: u16) u8,
    write: fn (self: *Self, address: u16, value: u8) void,
    readIo: fn (self: *Self, address: u8) u8,
    writeIo: fn (self: *Self, address: u8, value: u8) void,
};

const Instruction = fn (core: *Self) void;
const BindFn = fn (comptime func: anytype, comptime args: anytype) Instruction;

const Self = @This();

pc: u16 = 0,
a: u8 = 0,
flags: Flags = .{},
bc: u16 = 0,
de: u16 = 0,
hl: u16 = 0,
sp: u16 = 0,

pub fn init() Self {
    return .{};
}

pub fn format(self: *const Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("A={X:02} BC={X:04} DE={X:04} HL={X:04} SP={X:04} PC={X:04} F={c}{c}{c}{c}", .{
        self.a,
        self.bc,
        self.de,
        self.hl,
        self.sp,
        self.pc,
        @as(u8, if (self.flags.z) 'Z' else '-'),
        @as(u8, if (self.flags.n) 'N' else '-'),
        @as(u8, if (self.flags.h) 'H' else '-'),
        @as(u8, if (self.flags.c) 'C' else '-'),
    });
}

pub fn step(self: *Self, comptime iface: Interface) void {
    self.decode(iface)(self);
}

pub fn idle(self: *Self, comptime iface: Interface) void {
    fw.log.trace("  IO", .{});
    iface.idle(self);
}

pub fn read(self: *Self, comptime iface: Interface, address: u16) u8 {
    const value = iface.read(self, address);
    fw.log.trace("  {X:04} => {X:02}", .{ address, value });
    return value;
}

pub fn write(self: *Self, comptime iface: Interface, address: u16, value: u8) void {
    fw.log.trace("  {X:04} <= {X:02}", .{ address, value });
    iface.write(self, address, value);
}

pub fn readIo(self: *Self, comptime iface: Interface, address: u8) u8 {
    const value = iface.readIo(self, address);
    fw.log.trace("  FF{X:02} => {X:02}", .{ address, value });
    return value;
}

pub fn writeIo(self: *Self, comptime iface: Interface, address: u8, value: u8) void {
    fw.log.trace("  FF{X:02} <= {X:02}", .{ address, value });
    iface.writeIo(self, address, value);
}

pub fn nextByte(self: *Self, comptime iface: Interface) u8 {
    const value = self.read(iface, self.pc);
    self.pc +%= 1;
    return value;
}

pub fn nextWord(self: *Self, comptime iface: Interface) u16 {
    const lo = self.nextByte(iface);
    const hi = self.nextByte(iface);
    return (@as(u16, hi) << 8) | lo;
}

pub fn popWord(self: *Self, comptime iface: Interface) u16 {
    const lo = self.read(iface, self.sp);
    self.sp +%= 1;
    const hi = self.read(iface, self.sp);
    self.sp +%= 1;
    return (@as(u16, hi) << 8) | lo;
}

pub fn pushWord(self: *Self, comptime iface: Interface, value: u16) void {
    self.sp -%= 1;
    self.write(iface, self.sp, @truncate(value >> 8));
    self.sp -%= 1;
    self.write(iface, self.sp, @truncate(value));
}

fn decode(self: *Self, comptime iface: Interface) *const Instruction {
    const main_table = comptime opTable(iface);
    const cb_table = comptime opTableCb(iface);
    const opcode = self.nextByte(iface);

    if (opcode == 0xcb) {
        @branchHint(.unlikely);
        return cb_table[self.nextByte(iface)];
    } else {
        return main_table[opcode];
    }
}

fn opTable(comptime iface: Interface) [256]*const Instruction {
    const bind = bindFn(iface);

    var ops: [256]*const Instruction = undefined;

    inline for (0..256) |opcode| {
        ops[opcode] = bind(invalid, .{opcode});
    }

    // 0x00+0
    ops[0x18] = bind(control.jr, .{});
    ops[0x20] = bind(control.jrConditional, .NZ);
    ops[0x28] = bind(control.jrConditional, .Z);
    ops[0x30] = bind(control.jrConditional, .NC);
    ops[0x38] = bind(control.jrConditional, .C);

    // 0x00+1
    ops[0x01] = bind(load.ld16, .BC);
    ops[0x11] = bind(load.ld16, .DE);
    ops[0x21] = bind(load.ld16, .HL);
    ops[0x31] = bind(load.ld16, .SP);

    // 0x00+2
    ops[0x02] = bind(load.ld, .{ .BC_indirect, .A });
    ops[0x0a] = bind(load.ld, .{ .A, .BC_indirect });
    ops[0x12] = bind(load.ld, .{ .DE_indirect, .A });
    ops[0x1a] = bind(load.ld, .{ .A, .DE_indirect });
    ops[0x22] = bind(load.ld, .{ .HL_increment, .A });
    ops[0x2a] = bind(load.ld, .{ .A, .HL_increment });
    ops[0x32] = bind(load.ld, .{ .HL_decrement, .A });
    ops[0x3a] = bind(load.ld, .{ .A, .HL_decrement });

    // 0x00+3
    ops[0x03] = bind(alu.inc16, .BC);
    ops[0x0b] = bind(alu.dec16, .BC);
    ops[0x13] = bind(alu.inc16, .DE);
    ops[0x1b] = bind(alu.dec16, .DE);
    ops[0x23] = bind(alu.inc16, .HL);
    ops[0x2b] = bind(alu.dec16, .HL);
    ops[0x33] = bind(alu.inc16, .SP);
    ops[0x3b] = bind(alu.dec16, .SP);

    // 0x00+4
    ops[0x04] = bind(alu.inc, .B);
    ops[0x0c] = bind(alu.inc, .C);
    ops[0x14] = bind(alu.inc, .D);
    ops[0x1c] = bind(alu.inc, .E);
    ops[0x24] = bind(alu.inc, .H);
    ops[0x2c] = bind(alu.inc, .L);
    ops[0x34] = bind(alu.inc, .HL_indirect);
    ops[0x3c] = bind(alu.inc, .A);

    // 0x00+5
    ops[0x05] = bind(alu.inc, .B);
    ops[0x0d] = bind(alu.inc, .C);
    ops[0x15] = bind(alu.inc, .D);
    ops[0x1d] = bind(alu.inc, .E);
    ops[0x25] = bind(alu.inc, .H);
    ops[0x2d] = bind(alu.inc, .L);
    ops[0x35] = bind(alu.inc, .HL_indirect);
    ops[0x3d] = bind(alu.inc, .A);

    // 0x00+6
    ops[0x06] = bind(load.ld, .{ .B, .immediate });
    ops[0x0e] = bind(load.ld, .{ .C, .immediate });
    ops[0x16] = bind(load.ld, .{ .D, .immediate });
    ops[0x1e] = bind(load.ld, .{ .E, .immediate });
    ops[0x26] = bind(load.ld, .{ .H, .immediate });
    ops[0x2e] = bind(load.ld, .{ .L, .immediate });
    ops[0x36] = bind(load.ld, .{ .HL_indirect, .immediate });
    ops[0x3e] = bind(load.ld, .{ .A, .immediate });

    // 0x00+7
    ops[0x07] = bind(bit.rlca, .{});
    ops[0x0f] = bind(bit.rrca, .{});
    ops[0x17] = bind(bit.rla, .{});
    ops[0x1f] = bind(bit.rra, .{});

    // 0x40
    ops[0x40] = bind(load.ld, .{ .B, .B });
    ops[0x41] = bind(load.ld, .{ .B, .C });
    ops[0x42] = bind(load.ld, .{ .B, .D });
    ops[0x43] = bind(load.ld, .{ .B, .E });
    ops[0x44] = bind(load.ld, .{ .B, .H });
    ops[0x45] = bind(load.ld, .{ .B, .L });
    ops[0x46] = bind(load.ld, .{ .B, .HL_indirect });
    ops[0x47] = bind(load.ld, .{ .B, .A });

    // 0x48
    ops[0x48] = bind(load.ld, .{ .C, .B });
    ops[0x49] = bind(load.ld, .{ .C, .C });
    ops[0x4a] = bind(load.ld, .{ .C, .D });
    ops[0x4b] = bind(load.ld, .{ .C, .E });
    ops[0x4c] = bind(load.ld, .{ .C, .H });
    ops[0x4d] = bind(load.ld, .{ .C, .L });
    ops[0x4e] = bind(load.ld, .{ .C, .HL_indirect });
    ops[0x4f] = bind(load.ld, .{ .C, .A });

    // 0x50
    ops[0x50] = bind(load.ld, .{ .D, .B });
    ops[0x51] = bind(load.ld, .{ .D, .C });
    ops[0x52] = bind(load.ld, .{ .D, .D });
    ops[0x53] = bind(load.ld, .{ .D, .E });
    ops[0x54] = bind(load.ld, .{ .D, .H });
    ops[0x55] = bind(load.ld, .{ .D, .L });
    ops[0x56] = bind(load.ld, .{ .D, .HL_indirect });
    ops[0x57] = bind(load.ld, .{ .D, .A });

    // 0x58
    ops[0x58] = bind(load.ld, .{ .E, .B });
    ops[0x59] = bind(load.ld, .{ .E, .C });
    ops[0x5a] = bind(load.ld, .{ .E, .D });
    ops[0x5b] = bind(load.ld, .{ .E, .E });
    ops[0x5c] = bind(load.ld, .{ .E, .H });
    ops[0x5d] = bind(load.ld, .{ .E, .L });
    ops[0x5e] = bind(load.ld, .{ .E, .HL_indirect });
    ops[0x5f] = bind(load.ld, .{ .E, .A });

    // 0x60
    ops[0x60] = bind(load.ld, .{ .H, .B });
    ops[0x61] = bind(load.ld, .{ .H, .C });
    ops[0x62] = bind(load.ld, .{ .H, .D });
    ops[0x63] = bind(load.ld, .{ .H, .E });
    ops[0x64] = bind(load.ld, .{ .H, .H });
    ops[0x65] = bind(load.ld, .{ .H, .L });
    ops[0x66] = bind(load.ld, .{ .H, .HL_indirect });
    ops[0x67] = bind(load.ld, .{ .H, .A });

    // 0x68
    ops[0x68] = bind(load.ld, .{ .L, .B });
    ops[0x69] = bind(load.ld, .{ .L, .C });
    ops[0x6a] = bind(load.ld, .{ .L, .D });
    ops[0x6b] = bind(load.ld, .{ .L, .E });
    ops[0x6c] = bind(load.ld, .{ .L, .H });
    ops[0x6d] = bind(load.ld, .{ .L, .L });
    ops[0x6e] = bind(load.ld, .{ .L, .HL_indirect });
    ops[0x6f] = bind(load.ld, .{ .L, .A });

    // 0x70
    ops[0x70] = bind(load.ld, .{ .HL_indirect, .B });
    ops[0x71] = bind(load.ld, .{ .HL_indirect, .C });
    ops[0x72] = bind(load.ld, .{ .HL_indirect, .D });
    ops[0x73] = bind(load.ld, .{ .HL_indirect, .E });
    ops[0x74] = bind(load.ld, .{ .HL_indirect, .H });
    ops[0x75] = bind(load.ld, .{ .HL_indirect, .L });
    // ops[0x76] = bind(control.halt, .{});
    ops[0x77] = bind(load.ld, .{ .HL_indirect, .A });

    // 0x78
    ops[0x78] = bind(load.ld, .{ .A, .B });
    ops[0x79] = bind(load.ld, .{ .A, .C });
    ops[0x7a] = bind(load.ld, .{ .A, .D });
    ops[0x7b] = bind(load.ld, .{ .A, .E });
    ops[0x7c] = bind(load.ld, .{ .A, .H });
    ops[0x7d] = bind(load.ld, .{ .A, .L });
    ops[0x7e] = bind(load.ld, .{ .A, .HL_indirect });
    ops[0x7f] = bind(load.ld, .{ .A, .A });

    // 0x80
    ops[0x80] = bind(alu.add, .B);
    ops[0x81] = bind(alu.add, .C);
    ops[0x82] = bind(alu.add, .D);
    ops[0x83] = bind(alu.add, .E);
    ops[0x84] = bind(alu.add, .H);
    ops[0x85] = bind(alu.add, .L);
    ops[0x86] = bind(alu.add, .HL_indirect);
    ops[0x87] = bind(alu.add, .A);

    // 0x88
    ops[0x88] = bind(alu.adc, .B);
    ops[0x89] = bind(alu.adc, .C);
    ops[0x8a] = bind(alu.adc, .D);
    ops[0x8b] = bind(alu.adc, .E);
    ops[0x8c] = bind(alu.adc, .H);
    ops[0x8d] = bind(alu.adc, .L);
    ops[0x8e] = bind(alu.adc, .HL_indirect);
    ops[0x8f] = bind(alu.adc, .A);

    // 0x90
    ops[0x90] = bind(alu.sub, .B);
    ops[0x91] = bind(alu.sub, .C);
    ops[0x92] = bind(alu.sub, .D);
    ops[0x93] = bind(alu.sub, .E);
    ops[0x94] = bind(alu.sub, .H);
    ops[0x95] = bind(alu.sub, .L);
    ops[0x96] = bind(alu.sub, .HL_indirect);
    ops[0x97] = bind(alu.sub, .A);

    // 0x98
    ops[0x98] = bind(alu.sbc, .B);
    ops[0x99] = bind(alu.sbc, .C);
    ops[0x9a] = bind(alu.sbc, .D);
    ops[0x9b] = bind(alu.sbc, .E);
    ops[0x9c] = bind(alu.sbc, .H);
    ops[0x9d] = bind(alu.sbc, .L);
    ops[0x9e] = bind(alu.sbc, .HL_indirect);
    ops[0x9f] = bind(alu.sbc, .A);

    // 0xa0
    ops[0xa0] = bind(alu.and_, .B);
    ops[0xa1] = bind(alu.and_, .C);
    ops[0xa2] = bind(alu.and_, .D);
    ops[0xa3] = bind(alu.and_, .E);
    ops[0xa4] = bind(alu.and_, .H);
    ops[0xa5] = bind(alu.and_, .L);
    ops[0xa6] = bind(alu.and_, .HL_indirect);
    ops[0xa7] = bind(alu.and_, .A);

    // 0xa8
    ops[0xa8] = bind(alu.xor, .B);
    ops[0xa9] = bind(alu.xor, .C);
    ops[0xaa] = bind(alu.xor, .D);
    ops[0xab] = bind(alu.xor, .E);
    ops[0xac] = bind(alu.xor, .H);
    ops[0xad] = bind(alu.xor, .L);
    ops[0xae] = bind(alu.xor, .HL_indirect);
    ops[0xaf] = bind(alu.xor, .A);

    // 0xb0
    ops[0xb0] = bind(alu.or_, .B);
    ops[0xb1] = bind(alu.or_, .C);
    ops[0xb2] = bind(alu.or_, .D);
    ops[0xb3] = bind(alu.or_, .E);
    ops[0xb4] = bind(alu.or_, .H);
    ops[0xb5] = bind(alu.or_, .L);
    ops[0xb6] = bind(alu.or_, .HL_indirect);
    ops[0xb7] = bind(alu.or_, .A);

    // 0xb8
    ops[0xb8] = bind(alu.cp, .B);
    ops[0xb9] = bind(alu.cp, .C);
    ops[0xba] = bind(alu.cp, .D);
    ops[0xbb] = bind(alu.cp, .E);
    ops[0xbc] = bind(alu.cp, .H);
    ops[0xbd] = bind(alu.cp, .L);
    ops[0xbe] = bind(alu.cp, .HL_indirect);
    ops[0xbf] = bind(alu.cp, .A);

    // 0xc0+0
    ops[0xc0] = bind(control.retConditional, .NZ);
    ops[0xc8] = bind(control.retConditional, .Z);
    ops[0xd0] = bind(control.retConditional, .NC);
    ops[0xd8] = bind(control.retConditional, .C);
    ops[0xe0] = bind(load.ld, .{ .high, .A });
    ops[0xf0] = bind(load.ld, .{ .A, .high });

    // 0xc0+1
    ops[0xc1] = bind(load.pop, .BC);
    ops[0xc9] = bind(control.ret, .{});
    ops[0xd1] = bind(load.pop, .DE);
    ops[0xe1] = bind(load.pop, .HL);
    ops[0xf1] = bind(load.pop, .AF);

    // 0xc0+2
    ops[0xe2] = bind(load.ld, .{ .C_indirect, .A });
    ops[0xea] = bind(load.ld, .{ .absolute, .A });
    ops[0xf2] = bind(load.ld, .{ .A, .C_indirect });
    ops[0xfa] = bind(load.ld, .{ .A, .absolute });

    // 0xc0+4
    ops[0xc4] = bind(control.callConditional, .NZ);
    ops[0xcc] = bind(control.callConditional, .Z);
    ops[0xd4] = bind(control.callConditional, .NC);
    ops[0xdc] = bind(control.callConditional, .C);

    // 0xc0+5
    ops[0xc5] = bind(load.push, .BC);
    ops[0xcd] = bind(control.call, .{});
    ops[0xd5] = bind(load.push, .DE);
    ops[0xe5] = bind(load.push, .HL);
    ops[0xf5] = bind(load.push, .AF);

    // 0xc0+6
    ops[0xc6] = bind(alu.add, .immediate);
    ops[0xce] = bind(alu.adc, .immediate);
    ops[0xd6] = bind(alu.sub, .immediate);
    ops[0xde] = bind(alu.sbc, .immediate);
    ops[0xe6] = bind(alu.and_, .immediate);
    ops[0xee] = bind(alu.xor, .immediate);
    ops[0xf6] = bind(alu.or_, .immediate);
    ops[0xfe] = bind(alu.cp, .immediate);

    return ops;
}

fn opTableCb(comptime iface: Interface) [256]*const Instruction {
    const bind = bindFn(iface);

    var ops: [256]*const Instruction = undefined;

    // +0x00
    ops[0x00] = bind(bit.rlc, .B);
    ops[0x01] = bind(bit.rlc, .C);
    ops[0x02] = bind(bit.rlc, .D);
    ops[0x03] = bind(bit.rlc, .E);
    ops[0x04] = bind(bit.rlc, .H);
    ops[0x05] = bind(bit.rlc, .L);
    ops[0x06] = bind(bit.rlc, .HL_indirect);
    ops[0x07] = bind(bit.rlc, .A);

    // +0x08
    ops[0x08] = bind(bit.rrc, .B);
    ops[0x09] = bind(bit.rrc, .C);
    ops[0x0a] = bind(bit.rrc, .D);
    ops[0x0b] = bind(bit.rrc, .E);
    ops[0x0c] = bind(bit.rrc, .H);
    ops[0x0d] = bind(bit.rrc, .L);
    ops[0x0e] = bind(bit.rrc, .HL_indirect);
    ops[0x0f] = bind(bit.rrc, .A);

    // +0x10
    ops[0x10] = bind(bit.rl, .B);
    ops[0x11] = bind(bit.rl, .C);
    ops[0x12] = bind(bit.rl, .D);
    ops[0x13] = bind(bit.rl, .E);
    ops[0x14] = bind(bit.rl, .H);
    ops[0x15] = bind(bit.rl, .L);
    ops[0x16] = bind(bit.rl, .HL_indirect);
    ops[0x17] = bind(bit.rl, .A);

    // +0x18
    ops[0x18] = bind(bit.rr, .B);
    ops[0x19] = bind(bit.rr, .C);
    ops[0x1a] = bind(bit.rr, .D);
    ops[0x1b] = bind(bit.rr, .E);
    ops[0x1c] = bind(bit.rr, .H);
    ops[0x1d] = bind(bit.rr, .L);
    ops[0x1e] = bind(bit.rr, .HL_indirect);
    ops[0x1f] = bind(bit.rr, .A);

    // +0x20
    ops[0x20] = bind(bit.sla, .B);
    ops[0x21] = bind(bit.sla, .C);
    ops[0x22] = bind(bit.sla, .D);
    ops[0x23] = bind(bit.sla, .E);
    ops[0x24] = bind(bit.sla, .H);
    ops[0x25] = bind(bit.sla, .L);
    ops[0x26] = bind(bit.sla, .HL_indirect);
    ops[0x27] = bind(bit.sla, .A);

    // +0x28
    ops[0x28] = bind(bit.sra, .B);
    ops[0x29] = bind(bit.sra, .C);
    ops[0x2a] = bind(bit.sra, .D);
    ops[0x2b] = bind(bit.sra, .E);
    ops[0x2c] = bind(bit.sra, .H);
    ops[0x2d] = bind(bit.sra, .L);
    ops[0x2e] = bind(bit.sra, .HL_indirect);
    ops[0x2f] = bind(bit.sra, .A);

    // +0x30
    ops[0x30] = bind(bit.swap, .B);
    ops[0x31] = bind(bit.swap, .C);
    ops[0x32] = bind(bit.swap, .D);
    ops[0x33] = bind(bit.swap, .E);
    ops[0x34] = bind(bit.swap, .H);
    ops[0x35] = bind(bit.swap, .L);
    ops[0x36] = bind(bit.swap, .HL_indirect);
    ops[0x37] = bind(bit.swap, .A);

    // +0x38
    ops[0x38] = bind(bit.srl, .B);
    ops[0x39] = bind(bit.srl, .C);
    ops[0x3a] = bind(bit.srl, .D);
    ops[0x3b] = bind(bit.srl, .E);
    ops[0x3c] = bind(bit.srl, .H);
    ops[0x3d] = bind(bit.srl, .L);
    ops[0x3e] = bind(bit.srl, .HL_indirect);
    ops[0x3f] = bind(bit.srl, .A);

    inline for (0..8) |index| {
        const offset = index << 3;

        // +0x40
        ops[0x40 + offset] = bind(bit.bit, .{ index, .B });
        ops[0x41 + offset] = bind(bit.bit, .{ index, .C });
        ops[0x42 + offset] = bind(bit.bit, .{ index, .D });
        ops[0x43 + offset] = bind(bit.bit, .{ index, .E });
        ops[0x44 + offset] = bind(bit.bit, .{ index, .H });
        ops[0x45 + offset] = bind(bit.bit, .{ index, .L });
        ops[0x46 + offset] = bind(bit.bit, .{ index, .HL_increment });
        ops[0x47 + offset] = bind(bit.bit, .{ index, .A });

        // +0x80
        ops[0x80 + offset] = bind(bit.res, .{ index, .B });
        ops[0x81 + offset] = bind(bit.res, .{ index, .C });
        ops[0x82 + offset] = bind(bit.res, .{ index, .D });
        ops[0x83 + offset] = bind(bit.res, .{ index, .E });
        ops[0x84 + offset] = bind(bit.res, .{ index, .H });
        ops[0x85 + offset] = bind(bit.res, .{ index, .L });
        ops[0x86 + offset] = bind(bit.res, .{ index, .HL_increment });
        ops[0x87 + offset] = bind(bit.res, .{ index, .A });

        // +0xc0
        ops[0xc0 + offset] = bind(bit.set, .{ index, .B });
        ops[0xc1 + offset] = bind(bit.set, .{ index, .C });
        ops[0xc2 + offset] = bind(bit.set, .{ index, .D });
        ops[0xc3 + offset] = bind(bit.set, .{ index, .E });
        ops[0xc4 + offset] = bind(bit.set, .{ index, .H });
        ops[0xc5 + offset] = bind(bit.set, .{ index, .L });
        ops[0xc6 + offset] = bind(bit.set, .{ index, .HL_increment });
        ops[0xc7 + offset] = bind(bit.set, .{ index, .A });
    }

    return ops;
}

fn bindFn(comptime iface: Interface) BindFn {
    return struct {
        fn bind(comptime func: anytype, comptime args: anytype) Instruction {
            const is_tuple = switch (@typeInfo(@TypeOf(args))) {
                .@"struct" => |struc| struc.is_tuple,
                else => false,
            };

            const tuple_args = if (is_tuple) args else .{args};

            return struct {
                fn instr(core: *Self) void {
                    @call(.always_inline, func, tuple_args ++ .{ iface, core });
                }
            }.instr;
        }
    }.bind;
}

fn invalid(comptime opcode: u8, comptime iface: Interface, core: *Self) void {
    _ = core;
    _ = iface;
    fw.log.todo("SM83 opcode: {X:02}", .{opcode});
}
