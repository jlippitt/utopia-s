const std = @import("std");
const fw = @import("framework");
const alu = @import("./Sm83/alu.zig");
const load = @import("./Sm83/load.zig");

pub const Flags = packed struct(u8) {
    __: u4 = 0,
    c: bool = false,
    h: bool = false,
    n: bool = false,
    z: bool = false,
};

pub const Interface = struct {
    read: fn (self: *Self, address: u16) u8,
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
    const op_table = comptime opTable(iface);
    op_table[self.nextByte(iface)](self);
}

pub fn read(self: *Self, comptime iface: Interface, address: u16) u8 {
    const value = iface.read(self, address);
    fw.log.trace("  {X:04} => {X:02}", .{ address, value });
    return value;
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

fn opTable(comptime iface: Interface) [256]*const Instruction {
    const bind = bindFn(iface);

    var ops: [256]*const Instruction = undefined;

    inline for (0..256) |opcode| {
        ops[opcode] = bind(invalid, .{opcode});
    }

    // 0x00+1
    ops[0x01] = bind(load.ld16, .BC);
    ops[0x11] = bind(load.ld16, .DE);
    ops[0x21] = bind(load.ld16, .HL);
    ops[0x31] = bind(load.ld16, .SP);

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
