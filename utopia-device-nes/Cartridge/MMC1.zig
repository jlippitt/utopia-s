const std = @import("std");
const fw = @import("framework");
const Cartridge = @import("../Cartridge.zig");
const Self = @This();

shift: u5 = 0x10,
prg_rom_mode: u2 = 3,
prg_rom_bank: u4 = 0,
prg_ram_enabled: bool = true,
chr_mode: u1 = 0,
chr_bank: [2]u5 = @splat(0),

pub fn init(arena: *std.heap.ArenaAllocator, cartridge: *Cartridge) error{OutOfMemory}!Cartridge.Mapper {
    const self = try arena.allocator().create(Self);
    self.* = .{};

    cartridge.mapPrgRegisterWrite(8, 8);
    self.updateMappings(cartridge);

    return .init(self, .{
        .writeRegister = writeRegister,
    });
}

pub fn writeRegister(self: *Self, cartridge: *Cartridge, address: u16, value: u8) void {
    // TODO: Detect and ignore writes on consecutive cycles
    if (fw.num.bit(value, 7)) {
        self.shift = 0x10;
        self.prg_rom_mode = 3;
        fw.log.trace("MMC1 Shift: {X:02}", .{self.shift});
        fw.log.debug("MMC1 PRG ROM Mode: {}", .{self.prg_rom_mode});
        self.updateMappings(cartridge);
        return;
    }

    const value_ready = fw.num.bit(self.shift, 0);
    self.shift = (self.shift >> 1) | (@as(u5, @truncate((value & 0x01))) << 4);

    if (value_ready) {
        fw.log.debug("MMC1 Register Write: {X:04} <= {X:02}", .{ address, self.shift });
        self.writeRegisterInner(cartridge, address, self.shift);
        self.shift = 0x10;
    }

    fw.log.trace("MMC1 Shift: {X:02}", .{self.shift});
}

fn writeRegisterInner(self: *Self, cartridge: *Cartridge, address: u16, value: u5) void {
    switch (@as(u2, @truncate(address >> 13))) {
        0 => {
            cartridge.mapName(switch (@as(u2, @truncate(value))) {
                0 => @splat(.ci_ram_low),
                1 => @splat(.ci_ram_high),
                2 => Cartridge.NameMapping.mirror_vertical,
                3 => Cartridge.NameMapping.mirror_horizontal,
            });

            self.prg_rom_mode = @truncate(value >> 2);
            fw.log.debug("MMC1 PRG ROM Mode: {}", .{self.prg_rom_mode});

            self.chr_mode = @truncate(value >> 4);
            fw.log.debug("MMC1 CHR Mode: {}", .{self.chr_mode});
        },
        1 => {
            self.chr_bank[0] = value;
            fw.log.debug("MMC1 CHR Bank 0: {}", .{self.chr_bank[0]});
        },
        2 => {
            self.chr_bank[1] = value;
            fw.log.debug("MMC1 CHR Bank 1: {}", .{self.chr_bank[1]});
        },
        3 => {
            self.prg_rom_bank = @truncate(value);
            fw.log.debug("MMC1 PRG ROM Bank: {}", .{self.prg_rom_bank});

            self.prg_ram_enabled = !fw.num.bit(value, 4);
            fw.log.debug("MMC1 PRG RAM Enabled: {}", .{self.prg_ram_enabled});
        },
    }

    self.updateMappings(cartridge);
}

fn updateMappings(self: *const Self, cartridge: *Cartridge) void {
    switch (self.prg_rom_mode) {
        0, 1 => cartridge.mapPrgRom(8, 8, @as(i32, self.prg_rom_bank & 0x0e) * 4),
        2 => {
            cartridge.mapPrgRom(8, 4, 0);
            cartridge.mapPrgRom(12, 4, @as(i32, self.prg_rom_bank) * 4);
        },
        3 => {
            cartridge.mapPrgRom(8, 4, @as(i32, self.prg_rom_bank) * 4);
            cartridge.mapPrgRom(12, 4, -4);
        },
    }

    if (self.prg_ram_enabled) {
        cartridge.mapPrgRam(6, 2, 0);
    } else {
        cartridge.unmapPrg(6, 2);
    }

    switch (self.chr_mode) {
        0 => cartridge.mapChr(0, 8, @as(i32, self.chr_bank[0] & 0x1e) * 4),
        1 => {
            cartridge.mapChr(0, 4, @as(i32, self.chr_bank[0]) * 4);
            cartridge.mapChr(4, 4, @as(i32, self.chr_bank[1]) * 4);
        },
    }

    cartridge.printMappings();
}
