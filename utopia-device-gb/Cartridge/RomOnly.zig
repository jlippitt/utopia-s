const std = @import("std");
const Cartridge = @import("../Cartridge.zig");

const Self = @This();

pub fn init(
    arena: *std.heap.ArenaAllocator,
    cartridge: *Cartridge,
) error{OutOfMemory}!Cartridge.Mapper {
    const self = try arena.allocator().create(Self);
    self.* = .{};

    cartridge.mapRom(0, 0);
    cartridge.mapRom(1, 1);
    cartridge.mapRam(0);

    return .init(self, .{});
}
