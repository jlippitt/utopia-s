const std = @import("std");
const Cartridge = @import("../Cartridge.zig");

const chr_bank_size = 8;

const Self = @This();

pub fn init(
    arena: *std.heap.ArenaAllocator,
    cartridge: *Cartridge,
) error{OutOfMemory}!Cartridge.Mapper {
    const self = try arena.allocator().create(Self);
    self.* = .{};

    cartridge.mapPrgRam(6, 2, 0);
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
    cartridge.mapChr(0, 8, @as(i32, value & 0x0f) * chr_bank_size);
    cartridge.printMappings();
}
