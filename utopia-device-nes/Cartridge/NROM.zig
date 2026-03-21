const std = @import("std");
const Cartridge = @import("../Cartridge.zig");

const Self = @This();

pub fn init(
    arena: *std.heap.ArenaAllocator,
    cartridge: *Cartridge,
) error{OutOfMemory}!Cartridge.Mapper {
    const self = try arena.allocator().create(Self);
    self.* = .{};

    cartridge.mapPrgRam(6, 2, 0);
    cartridge.mapPrgRom(8, 8, 0);
    cartridge.mapChr(0, 8, 0);
    cartridge.printMappings();

    return .init(self, .{});
}
