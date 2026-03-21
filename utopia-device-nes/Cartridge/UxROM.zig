const std = @import("std");
const Cartridge = @import("../Cartridge.zig");

const Self = @This();

pub fn init(
    arena: *std.heap.ArenaAllocator,
    cartridge: *Cartridge,
) error{OutOfMemory}!Cartridge.Mapper {
    const self = try arena.allocator().create(Self);
    self.* = .{};

    cartridge.mapPrgRom(8, 4, 0);
    cartridge.mapPrgRom(12, 4, -4);
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
    cartridge.mapPrgRom(8, 4, @as(i32, value & 0x0f) * 4);
    cartridge.printMappings();
}
