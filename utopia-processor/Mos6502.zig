const std = @import("std");
const fw = @import("framework");
const control = @import("./Mos6502/control.zig");
const interrupt = @import("./Mos6502/interrupt.zig");
const implied = @import("./Mos6502/implied.zig").implied;
const load = @import("./Mos6502/load.zig").load;
const modify = @import("./Mos6502/modify.zig");
const stack = @import("./Mos6502/stack.zig");
const store = @import("./Mos6502/store.zig").store;

pub const stack_page: u16 = 0x0100;

pub const Flags = packed struct(u8) {
    c: bool = false,
    z: bool = false,
    i: bool = false,
    d: bool = false,
    __: u2 = 0b11,
    v: bool = false,
    n: bool = false,
};

pub const Interrupt = packed struct(u8) {
    reset: bool = false,
    nmi: bool = false,
    irq: bool = false,
    __: u5 = 0,
};

pub const Interface = struct {
    read: fn (self: *Self, address: u16) u8,
    write: fn (self: *Self, address: u16, value: u8) void,
};

const Instruction = fn (core: *Self) void;
const BindFn = fn (comptime func: anytype, comptime args: anytype) Instruction;

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

pub fn setNmi(self: *Self, active: bool) void {
    self.int_active.nmi = active;
}

pub fn setIrq(self: *Self, active: bool) void {
    self.int_active.irq = active;
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
            interrupt.nmi(iface, self);
        } else {
            interrupt.irq(iface, self);
        }

        self.int_polled = .{};
        return;
    }

    const op_table = comptime opTable(iface);

    op_table[self.next(iface)](self);
}

pub fn poll(self: *Self) void {
    // Interrupt and Flags structures are arranged so that IRQ signal and
    // IRQ inhibit flag are both bit 3 (0x04)
    self.int_polled = @bitCast(@as(u8, @bitCast(self.int_active)) &
        ~(@as(u8, @bitCast(self.flags)) & 0x04));
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

pub fn next(self: *Self, comptime iface: Interface) u8 {
    const value = self.read(iface, self.pc);
    self.pc +%= 1;
    return value;
}

pub fn pull(self: *Self, comptime iface: Interface) u8 {
    self.s +%= 1;
    return self.read(iface, stack_page | self.s);
}

pub fn push(self: *Self, comptime iface: Interface, value: u8) void {
    self.write(iface, stack_page | self.s, value);
    self.s -%= 1;
}

pub fn setNz(self: *Self, value: u8) void {
    self.flags.n = fw.num.bit(value, 7);
    self.flags.z = value == 0;
}

fn opTable(comptime iface: Interface) [256]*const Instruction {
    const bind = bindFn(iface);

    var ops: [256]*const Instruction = undefined;

    inline for (0..256) |opcode| {
        ops[opcode] = bind(invalid, .{opcode});
    }

    // +0x00
    ops[0x00] = bind(interrupt.brk, .{});
    ops[0x20] = bind(control.jsr, .{});
    ops[0x40] = bind(interrupt.rti, .{});
    ops[0x60] = bind(control.rts, .{});
    ops[0xa0] = bind(load, .{ .LDY, .immediate });
    ops[0xc0] = bind(load, .{ .CPY, .immediate });
    ops[0xe0] = bind(load, .{ .CPX, .immediate });

    // +0x10
    ops[0x10] = bind(control.branch, .BPL);
    ops[0x30] = bind(control.branch, .BMI);
    ops[0x50] = bind(control.branch, .BVC);
    ops[0x70] = bind(control.branch, .BVS);
    ops[0x90] = bind(control.branch, .BCC);
    ops[0xb0] = bind(control.branch, .BCS);
    ops[0xd0] = bind(control.branch, .BNE);
    ops[0xf0] = bind(control.branch, .BEQ);

    // +0x04
    ops[0x24] = bind(load, .{ .BIT, .zero_page });
    ops[0x84] = bind(store, .{ .STY, .zero_page });
    ops[0xa4] = bind(load, .{ .LDY, .zero_page });
    ops[0xc4] = bind(load, .{ .CPY, .zero_page });
    ops[0xe4] = bind(load, .{ .CPX, .zero_page });

    // +0x14
    ops[0x94] = bind(store, .{ .STY, .zero_page_x });
    ops[0xb4] = bind(load, .{ .LDY, .zero_page_x });

    // +0x08
    ops[0x08] = bind(stack.php, .{});
    ops[0x28] = bind(stack.plp, .{});
    ops[0x48] = bind(stack.pha, .{});
    ops[0x68] = bind(stack.pla, .{});
    ops[0x88] = bind(implied, .DEY);
    ops[0xa8] = bind(implied, .TAY);
    ops[0xc8] = bind(implied, .INY);
    ops[0xe8] = bind(implied, .INX);

    // +0x18
    ops[0x18] = bind(implied, .CLC);
    ops[0x38] = bind(implied, .SEC);
    ops[0x58] = bind(implied, .CLI);
    ops[0x78] = bind(implied, .SEI);
    ops[0x98] = bind(implied, .TYA);
    ops[0xb8] = bind(implied, .CLV);
    ops[0xd8] = bind(implied, .CLD);
    ops[0xf8] = bind(implied, .SED);

    // +0x0c
    ops[0x2c] = bind(load, .{ .BIT, .absolute });
    ops[0x4c] = bind(control.jmp, .{});
    ops[0x6c] = bind(control.jmpIndirect, .{});
    ops[0x8c] = bind(store, .{ .STY, .absolute });
    ops[0xac] = bind(load, .{ .LDY, .absolute });
    ops[0xcc] = bind(load, .{ .CPY, .absolute });
    ops[0xec] = bind(load, .{ .CPX, .absolute });

    // +0x1c
    ops[0xbc] = bind(load, .{ .LDY, .absolute_x });

    // +0x01
    ops[0x01] = bind(load, .{ .ORA, .zero_page_x_indirect });
    ops[0x21] = bind(load, .{ .AND, .zero_page_x_indirect });
    ops[0x41] = bind(load, .{ .EOR, .zero_page_x_indirect });
    ops[0x61] = bind(load, .{ .ADC, .zero_page_x_indirect });
    ops[0x81] = bind(store, .{ .STA, .zero_page_x_indirect });
    ops[0xa1] = bind(load, .{ .LDA, .zero_page_x_indirect });
    ops[0xc1] = bind(load, .{ .CMP, .zero_page_x_indirect });
    ops[0xe1] = bind(load, .{ .SBC, .zero_page_x_indirect });

    // +0x11
    ops[0x11] = bind(load, .{ .ORA, .zero_page_indirect_y });
    ops[0x31] = bind(load, .{ .AND, .zero_page_indirect_y });
    ops[0x51] = bind(load, .{ .EOR, .zero_page_indirect_y });
    ops[0x71] = bind(load, .{ .ADC, .zero_page_indirect_y });
    ops[0x91] = bind(store, .{ .STA, .zero_page_indirect_y });
    ops[0xb1] = bind(load, .{ .LDA, .zero_page_indirect_y });
    ops[0xd1] = bind(load, .{ .CMP, .zero_page_indirect_y });
    ops[0xf1] = bind(load, .{ .SBC, .zero_page_indirect_y });

    // +0x05
    ops[0x05] = bind(load, .{ .ORA, .zero_page });
    ops[0x25] = bind(load, .{ .AND, .zero_page });
    ops[0x45] = bind(load, .{ .EOR, .zero_page });
    ops[0x65] = bind(load, .{ .ADC, .zero_page });
    ops[0x85] = bind(store, .{ .STA, .zero_page });
    ops[0xa5] = bind(load, .{ .LDA, .zero_page });
    ops[0xc5] = bind(load, .{ .CMP, .zero_page });
    ops[0xe5] = bind(load, .{ .SBC, .zero_page });

    // +0x15
    ops[0x15] = bind(load, .{ .ORA, .zero_page_x });
    ops[0x35] = bind(load, .{ .AND, .zero_page_x });
    ops[0x55] = bind(load, .{ .EOR, .zero_page_x });
    ops[0x75] = bind(load, .{ .ADC, .zero_page_x });
    ops[0x95] = bind(store, .{ .STA, .zero_page_x });
    ops[0xb5] = bind(load, .{ .LDA, .zero_page_x });
    ops[0xd5] = bind(load, .{ .CMP, .zero_page_x });
    ops[0xf5] = bind(load, .{ .SBC, .zero_page_x });

    // +0x09
    ops[0x09] = bind(load, .{ .ORA, .immediate });
    ops[0x29] = bind(load, .{ .AND, .immediate });
    ops[0x49] = bind(load, .{ .EOR, .immediate });
    ops[0x69] = bind(load, .{ .ADC, .immediate });
    ops[0xa9] = bind(load, .{ .LDA, .immediate });
    ops[0xc9] = bind(load, .{ .CMP, .immediate });
    ops[0xe9] = bind(load, .{ .SBC, .immediate });

    // +0x19
    ops[0x19] = bind(load, .{ .ORA, .absolute_y });
    ops[0x39] = bind(load, .{ .AND, .absolute_y });
    ops[0x59] = bind(load, .{ .EOR, .absolute_y });
    ops[0x79] = bind(load, .{ .ADC, .absolute_y });
    ops[0x99] = bind(store, .{ .STA, .absolute_y });
    ops[0xb9] = bind(load, .{ .LDA, .absolute_y });
    ops[0xd9] = bind(load, .{ .CMP, .absolute_y });
    ops[0xf9] = bind(load, .{ .SBC, .absolute_y });

    // +0x0d
    ops[0x0d] = bind(load, .{ .ORA, .absolute });
    ops[0x2d] = bind(load, .{ .AND, .absolute });
    ops[0x4d] = bind(load, .{ .EOR, .absolute });
    ops[0x6d] = bind(load, .{ .ADC, .absolute });
    ops[0x8d] = bind(store, .{ .STA, .absolute });
    ops[0xad] = bind(load, .{ .LDA, .absolute });
    ops[0xcd] = bind(load, .{ .CMP, .absolute });
    ops[0xed] = bind(load, .{ .SBC, .absolute });

    // +0x1d
    ops[0x1d] = bind(load, .{ .ORA, .absolute_x });
    ops[0x3d] = bind(load, .{ .AND, .absolute_x });
    ops[0x5d] = bind(load, .{ .EOR, .absolute_x });
    ops[0x7d] = bind(load, .{ .ADC, .absolute_x });
    ops[0x9d] = bind(store, .{ .STA, .absolute_x });
    ops[0xbd] = bind(load, .{ .LDA, .absolute_x });
    ops[0xdd] = bind(load, .{ .CMP, .absolute_x });
    ops[0xfd] = bind(load, .{ .SBC, .absolute_x });

    // +0x02
    ops[0xa2] = bind(load, .{ .LDX, .immediate });

    // +0x06
    ops[0x06] = bind(modify.memory, .{ .ASL, .zero_page });
    ops[0x26] = bind(modify.memory, .{ .ROL, .zero_page });
    ops[0x46] = bind(modify.memory, .{ .LSR, .zero_page });
    ops[0x66] = bind(modify.memory, .{ .ROR, .zero_page });
    ops[0x86] = bind(store, .{ .STX, .zero_page });
    ops[0xa6] = bind(load, .{ .LDX, .zero_page });
    ops[0xc6] = bind(modify.memory, .{ .DEC, .zero_page });
    ops[0xe6] = bind(modify.memory, .{ .INC, .zero_page });

    // +0x16
    ops[0x16] = bind(modify.memory, .{ .ASL, .zero_page_x });
    ops[0x36] = bind(modify.memory, .{ .ROL, .zero_page_x });
    ops[0x56] = bind(modify.memory, .{ .LSR, .zero_page_x });
    ops[0x76] = bind(modify.memory, .{ .ROR, .zero_page_x });
    ops[0x96] = bind(store, .{ .STX, .zero_page_y });
    ops[0xb6] = bind(load, .{ .LDX, .zero_page_y });
    ops[0xd6] = bind(modify.memory, .{ .DEC, .zero_page_x });
    ops[0xf6] = bind(modify.memory, .{ .INC, .zero_page_x });

    // +0x0a
    ops[0x0a] = bind(modify.accumulator, .ASL);
    ops[0x2a] = bind(modify.accumulator, .ROL);
    ops[0x4a] = bind(modify.accumulator, .LSR);
    ops[0x6a] = bind(modify.accumulator, .ROR);
    ops[0x8a] = bind(implied, .TXA);
    ops[0xaa] = bind(implied, .TAX);
    ops[0xca] = bind(implied, .DEX);
    ops[0xea] = bind(implied, .NOP);

    // +0x1a
    ops[0x9a] = bind(implied, .TXS);
    ops[0xba] = bind(implied, .TSX);

    // +0x0e
    ops[0x0e] = bind(modify.memory, .{ .ASL, .absolute });
    ops[0x2e] = bind(modify.memory, .{ .ROL, .absolute });
    ops[0x4e] = bind(modify.memory, .{ .LSR, .absolute });
    ops[0x6e] = bind(modify.memory, .{ .ROR, .absolute });
    ops[0x8e] = bind(store, .{ .STX, .absolute });
    ops[0xae] = bind(load, .{ .LDX, .absolute });
    ops[0xce] = bind(modify.memory, .{ .DEC, .absolute });
    ops[0xee] = bind(modify.memory, .{ .INC, .absolute });

    // +0x1e
    ops[0x1e] = bind(modify.memory, .{ .ASL, .absolute_x });
    ops[0x3e] = bind(modify.memory, .{ .ROL, .absolute_x });
    ops[0x5e] = bind(modify.memory, .{ .LSR, .absolute_x });
    ops[0x7e] = bind(modify.memory, .{ .ROR, .absolute_x });
    ops[0xbe] = bind(load, .{ .LDX, .absolute_y });
    ops[0xde] = bind(modify.memory, .{ .DEC, .absolute_x });
    ops[0xfe] = bind(modify.memory, .{ .INC, .absolute_x });

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
    fw.log.todo("MOS-6502 opcode: {X:02}", .{opcode});
}
