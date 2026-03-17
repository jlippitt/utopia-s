const std = @import("std");
const fw = @import("framework");
const interrupt = @import("./Mos6502/interrupt.zig");
const implied = @import("./Mos6502/implied.zig").implied;

pub const stack_page: u16 = 0x0100;

pub const Flags = packed struct(u8) {
    c: bool = false,
    z: bool = false,
    i: bool = false,
    d: bool = false,
    __: u2 = 0,
    v: bool = false,
    n: bool = false,
};

pub const Interrupt = packed struct(u8) {
    reset: bool = false,
    nmi: bool = false,
    irq: u6 = 0,
};

pub const Instruction = fn (core: *Self) void;

pub const Interface = struct {
    read: fn (self: *Self, address: u16) u8,
};

const Self = @This();

pc: u16 = 0,
a: u8 = 0,
x: u8 = 0,
y: u8 = 0,
s: u8 = 0,
flags: Flags = .{},
int_active: Interrupt = .{},
int_polled: Interrupt = .{},

pub fn init(reset: bool) Self {
    return .{
        .int_polled = .{
            .reset = reset,
        },
    };
}

pub fn format(self: *const Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("A={X:02} X={X:02} Y={X:02} S={X:02} PC={X:04} P={c}{c}--{c}{c}{c}{c}", .{
        self.a,
        self.x,
        self.y,
        self.s,
        self.pc,
        @as(u8, if (self.flags.n) 'N' else '-'),
        @as(u8, if (self.flags.v) 'V' else '-'),
        @as(u8, if (self.flags.d) 'D' else '-'),
        @as(u8, if (self.flags.i) 'I' else '-'),
        @as(u8, if (self.flags.z) 'Z' else '-'),
        @as(u8, if (self.flags.c) 'C' else '-'),
    });
}

pub fn step(self: *Self, comptime iface: Interface) void {
    if (@as(u8, @bitCast(self.int_polled)) != 0) {
        @branchHint(.unlikely);

        _ = self.read(iface, self.pc);

        if (self.int_polled.reset) {
            self.int_active.reset = false;
            interrupt.reset(iface, self);
        } else if (self.int_polled.nmi) {
            self.int_active.nmi = false;
            fw.log.todo("NMI", .{});
        } else {
            fw.log.todo("IRQ", .{});
        }

        self.int_polled = .{};
        return;
    }

    const op_table = comptime opTable(iface);

    op_table[self.next(iface)](self);
}

pub fn poll(self: *Self) void {
    self.int_polled = self.int_active;

    if (self.flags.i) {
        self.int_polled.irq = 0;
    }
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
    var ops: [256]*const Instruction = undefined;

    inline for (0..256) |opcode| {
        ops[opcode] = bind(invalid, .{opcode});
    }

    ops[0x18] = bind(implied, .{ iface, .CLC });
    ops[0x38] = bind(implied, .{ iface, .SEC });
    ops[0x58] = bind(implied, .{ iface, .CLI });
    ops[0x78] = bind(implied, .{ iface, .SEI });
    ops[0xb8] = bind(implied, .{ iface, .CLV });
    ops[0xd8] = bind(implied, .{ iface, .CLD });
    ops[0xf8] = bind(implied, .{ iface, .SED });

    return ops;
}

fn bind(comptime func: anytype, comptime args: anytype) Instruction {
    return struct {
        fn instr(core: *Self) void {
            @call(.always_inline, func, args ++ .{core});
        }
    }.instr;
}

fn invalid(comptime opcode: u8, core: *Self) void {
    _ = core;
    fw.log.todo("MOS-6502 opcode: {X:02}", .{opcode});
}
