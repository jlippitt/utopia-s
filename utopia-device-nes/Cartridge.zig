const std = @import("std");
const fw = @import("framework");

const ines_string: []const u8 = &.{ 0x4e, 0x45, 0x53, 0x1a };

const header_size = 16;
const trainer_size = 512;
const prg_rom_multiplier = 16384;
const chr_rom_multiplier = 8192;

const ci_ram_size = 2048;

var test_rom_buf: [256]u8 = undefined;
var test_rom_writer = std.fs.File.stderr().writer(&test_rom_buf);

const Self = @This();

prg_rom: []const u8,
prg_rom_mask: usize,
chr_data: []u8,
chr_writable: bool,
vram_address: u15 = 0,
name_mapping: [4]NameMapping,
ci_ram: *[ci_ram_size]u8,

pub fn init(arena: *std.heap.ArenaAllocator, rom: []const u8) error{ ArgError, OutOfMemory }!Self {
    if (!std.mem.eql(u8, ines_string, rom[0..4])) {
        fw.log.panic("Not a valid INES ROM", .{});
    }

    const prg_rom_begin = header_size + @as(u32, if (fw.num.bit(rom[6], 2)) trainer_size else 0);

    const prg_rom_size = @as(u32, rom[4]) * prg_rom_multiplier;
    fw.log.debug("PRG ROM Size: {d}", .{prg_rom_size});

    std.debug.assert(std.math.isPowerOfTwo(prg_rom_size));

    const prg_rom = rom[prg_rom_begin..][0..prg_rom_size];
    const prg_rom_mask = prg_rom_size - 1;

    const chr_rom_size = @as(u32, rom[5]) * chr_rom_multiplier;
    fw.log.debug("CHR ROM Size: {d}", .{chr_rom_size});

    const chr_data, const chr_writable = if (chr_rom_size == 0)
        .{
            try arena.allocator().alloc(u8, chr_rom_multiplier),
            true,
        }
    else
        .{
            @constCast(rom[(prg_rom_begin + prg_rom_size)..][0..chr_rom_size]),
            false,
        };

    const name_mapping = if (fw.num.bit(rom[6], 0)) blk: {
        fw.log.debug("Default Mirror Mode: Vertical", .{});
        break :blk NameMapping.mirror_vertical;
    } else blk: {
        fw.log.debug("Default Mirror Mode: Horizontal", .{});
        break :blk NameMapping.mirror_horizontal;
    };

    fw.log.debug("Default Name Mapping: {any}", .{name_mapping});

    const ci_ram = try arena.allocator().alloc(u8, ci_ram_size);

    return .{
        .prg_rom = prg_rom,
        .prg_rom_mask = prg_rom_mask,
        .chr_data = chr_data,
        .chr_writable = chr_writable,
        .name_mapping = name_mapping,
        .ci_ram = ci_ram[0..ci_ram_size],
    };
}

pub fn readPrg(self: *const Self, address: u16, prev_value: u8) u8 {
    if (address < 0x8000) {
        // TODO: PRG RAM
        return prev_value;
    }

    return self.prg_rom[address & self.prg_rom_mask];
}

pub fn writePrg(self: *const Self, address: u16, value: u8) void {
    _ = self;

    if (address >= 0x6004 and address <= 0x8000) {
        var writer = &test_rom_writer.interface;
        writer.writeByte(value) catch {};
        writer.flush() catch {};
    }

    // TODO: PRG RAM + Mappers
}

pub fn setVramAddress(self: *Self, address: u15) void {
    self.vram_address = address;
}

pub fn readVram(self: *Self) u8 {
    if ((self.vram_address & 0x2000) == 0) {
        return self.chr_data[@as(u13, @truncate(self.vram_address))];
    }

    return switch (self.name_mapping[@as(u2, @truncate(self.vram_address >> 10))]) {
        .ci_ram => |offset| self.ci_ram[offset | @as(u10, @truncate(self.vram_address))],
        .custom => fw.log.todo("Custom nametable mappings", .{}),
    };
}

pub fn writeVram(self: *Self, value: u8) void {
    if ((self.vram_address & 0x2000) == 0) {
        if (self.chr_writable) {
            self.chr_data[@as(u13, @truncate(self.vram_address))] = value;
        } else {
            fw.log.warn("Write to CHR ROM area: {X:04}", .{self.vram_address});
        }

        return;
    }

    switch (self.name_mapping[@as(u2, @truncate(self.vram_address >> 10))]) {
        .ci_ram => |offset| self.ci_ram[offset | @as(u10, @truncate(self.vram_address))] = value,
        .custom => fw.log.todo("Custom nametable mappings", .{}),
    }
}

pub const NameMapping = union(enum) {
    ci_ram: u11,
    custom: void,

    pub const ci_ram_low: NameMapping = .{ .ci_ram = 0 };
    pub const ci_ram_high: NameMapping = .{ .ci_ram = 1024 };

    pub const mirror_horizontal: [4]NameMapping = .{
        ci_ram_low,
        ci_ram_low,
        ci_ram_high,
        ci_ram_high,
    };

    pub const mirror_vertical: [4]NameMapping = .{
        ci_ram_low,
        ci_ram_high,
        ci_ram_low,
        ci_ram_high,
    };
};
