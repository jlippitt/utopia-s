const std = @import("std");
const fw = @import("framework");

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
    op_table[self.next(iface)](self);
}

pub fn read(self: *Self, comptime iface: Interface, address: u16) u8 {
    const value = iface.read(self, address);
    fw.log.trace("  {X:04} => {X:02}", .{ address, value });
    return value;
}

pub fn next(self: *Self, comptime iface: Interface) u8 {
    const value = self.read(iface, self.pc);
    self.pc +%= 1;
    return value;
}

fn opTable(comptime iface: Interface) [256]*const Instruction {
    const bind = bindFn(iface);

    var ops: [256]*const Instruction = undefined;

    inline for (0..256) |opcode| {
        ops[opcode] = bind(invalid, .{opcode});
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
