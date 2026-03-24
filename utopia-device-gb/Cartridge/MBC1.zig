const std = @import("std");
const fw = @import("framework");
const Cartridge = @import("../Cartridge.zig");

const Self = @This();

ram_enable: bool = false,
bank_lower: u5 = 0,
bank_upper: u2 = 0,
bank_mode: u1 = 0,

pub fn init(
    arena: *std.heap.ArenaAllocator,
    cartridge: *Cartridge,
) error{OutOfMemory}!Cartridge.Mapper {
    const self = try arena.allocator().create(Self);
    self.* = .{};

    self.updateMappings(cartridge);

    return .init(self, .{
        .writeRegister = writeRegister,
    });
}

pub fn writeRegister(self: *Self, cartridge: *Cartridge, address: u16, value: u8) void {
    switch (@as(u2, @truncate(address >> 13))) {
        0 => {
            self.ram_enable = (value & 0x0f) == 0x0a;
            fw.log.debug("MBC1 RAM Enable: {}", .{self.ram_enable});
        },
        1 => {
            self.bank_lower = @truncate(value);
            fw.log.debug("MBC1 Bank (Lower): {}", .{self.bank_lower});
        },
        2 => {
            self.bank_upper = @truncate(value);
            fw.log.debug("MBC1 Bank (Upper): {}", .{self.bank_upper});
        },
        3 => {
            self.bank_mode = @truncate(value);
            fw.log.debug("MBC1 Bank Mode: {}", .{self.bank_mode});
        },
    }

    self.updateMappings(cartridge);
}

pub fn updateMappings(self: *const Self, cartridge: *Cartridge) void {
    cartridge.mapRom(0, switch (self.bank_mode) {
        0 => 0,
        1 => (@as(u32, self.bank_upper) << 5),
    });

    cartridge.mapRom(1, (@as(u32, self.bank_upper) << 5) | self.bank_lower);

    if (self.ram_enable) {
        cartridge.mapRam(switch (self.bank_mode) {
            0 => 0,
            1 => @as(u32, self.bank_upper),
        });
    } else {
        cartridge.unmapRam();
    }

    cartridge.printMappings();
}
