const std = @import("std");
const fw = @import("framework");

const bank_size = 16384;
const bank_mask = bank_size - 1;

const Self = @This();

mapping: [3]Mapping = @splat(.{ .rom = 0 }),
rom: []const u8,
rom_mask: u32,
ram: []u8,
ram_mask: u32,
ctrl: Control = .{},
rom_bank: [3]u8 = @splat(0),

pub fn init(arena: *std.heap.ArenaAllocator, vfs: fw.Vfs) fw.Vfs.Error!Self {
    const rom = try vfs.readRom(arena.allocator());
    const rom_mask = (std.math.ceilPowerOfTwo(usize, rom.len) catch unreachable) - 1;

    // TODO: Detect RAM size. For now, allocate 32K in all cases.
    const ram_size = bank_size * 2;
    const ram = try arena.allocator().alloc(u8, ram_size);

    return .{
        .rom = rom,
        .rom_mask = @intCast(rom_mask),
        .ram = ram,
        .ram_mask = @intCast(ram_size - 1),
    };
}

pub fn read(self: *const Self, address: u16, prev_value: u8) u8 {
    // TODO: Other mappers
    if (address <= 0x0400) {
        return self.rom[address];
    }

    if (address <= 0xc000) {
        return switch (self.mapping[address >> 14]) {
            .rom => |offset| self.rom[offset | (address & bank_mask & self.rom_mask)],
            .ram => |offset| self.ram[offset | (address & bank_mask & self.ram_mask)],
        };
    }

    return prev_value;
}

pub fn write(self: *Self, address: u16, value: u8) void {
    // TODO: Other mappers
    if (address <= 0xc000) {
        switch (self.mapping[address >> 14]) {
            .rom => fw.log.panic("Write to ROM area: {X:04} <= {X:02}", .{ address, value }),
            .ram => |offset| self.ram[offset | (address & bank_mask & self.ram_mask)] = value,
        }
        return;
    }

    if (address <= 0xfffc) {
        return;
    }

    switch (@as(u2, @truncate(address))) {
        0 => {
            self.ctrl = @bitCast(value);
            fw.log.debug("Mapper Control: {any}", .{self.ctrl});

            if (self.ctrl.bank_shift != 0) {
                fw.log.unimplemented("ROM bank shift", .{});
            }
        },
        else => |index| {
            const bank = index - 1;
            self.rom_bank[bank] = value;
            fw.log.debug("Mapper ROM Bank {d}: {any}", .{ bank, self.rom_bank[bank] });
        },
    }

    self.mapping[0] = .{ .rom = map(self.rom_bank[0], self.rom_mask) };

    self.mapping[1] = if (self.ctrl.ram_enable_1)
        .{ .ram = map(self.ctrl.ram_bank, self.rom_mask) }
    else
        .{ .rom = map(self.rom_bank[1], self.rom_mask) };

    self.mapping[2] = if (self.ctrl.ram_enable_2)
        .{ .ram = map(self.ctrl.ram_bank, self.rom_mask) }
    else
        .{ .rom = map(self.rom_bank[2], self.rom_mask) };

    fw.log.debug("Mapping: {any}", .{self.mapping});
}

fn map(bank: u8, mask: u32) u32 {
    return (@as(u32, bank) * bank_size) & mask;
}

const Mapping = union(enum) {
    rom: u32,
    ram: u32,
};

const Control = packed struct(u8) {
    bank_shift: u2 = 0,
    ram_bank: u1 = 0,
    ram_enable_1: bool = false,
    ram_enable_2: bool = false,
    __: u2 = 0,
    rom_write: bool = false,
};
