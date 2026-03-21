const std = @import("std");
const fw = @import("framework");
const Cartridge = @import("../Cartridge.zig");

const prg_rom_bank_size = 8;

const Self = @This();

pub fn init(
    arena: *std.heap.ArenaAllocator,
    cartridge: *Cartridge,
) error{OutOfMemory}!Cartridge.Mapper {
    const self = try arena.allocator().create(Self);
    self.* = .{};

    cartridge.mapPrgRom(8, 8, 0);
    cartridge.mapPrgRegisterWrite(8, 8);
    cartridge.mapChr(0, 8, 0);
    cartridge.printMappings();

    return .init(self, .{
        .writeRegister = writeRegister,
    });
}

pub fn writeRegister(self: *Self, cartridge: *Cartridge, address: u16, value: u8) void {
    _ = self;
    _ = address;
    cartridge.mapPrgRom(8, 8, @as(i32, value & 0x07) * prg_rom_bank_size);
    cartridge.mapName(@splat(if (fw.num.bit(value, 4)) .ci_ram_high else .ci_ram_low));
    cartridge.printMappings();
}
