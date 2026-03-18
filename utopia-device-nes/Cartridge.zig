const std = @import("std");
const fw = @import("framework");

const ines_string: []const u8 = &.{ 0x4e, 0x45, 0x53, 0x1a };

const header_size = 16;
const trainer_size = 512;
const prg_rom_multiplier = 16384;

var test_rom_buf: [256]u8 = undefined;
var test_rom_writer = std.fs.File.stderr().writer(&test_rom_buf);

const Self = @This();

prg_rom: []const u8,
prg_rom_mask: usize,

pub fn init(rom: []const u8) error{ArgError}!Self {
    if (!std.mem.eql(u8, ines_string, rom[0..4])) {
        fw.log.panic("Not a valid INES ROM", .{});
    }

    const prg_rom_begin = header_size + @as(u32, if (fw.num.bit(rom[6], 2)) trainer_size else 0);

    const prg_rom_size = @as(u32, rom[4]) * prg_rom_multiplier;
    fw.log.debug("PRG ROM Size: {d}", .{prg_rom_size});

    std.debug.assert(std.math.isPowerOfTwo(prg_rom_size));

    const prg_rom = rom[prg_rom_begin..][0..prg_rom_size];
    const prg_rom_mask = prg_rom_size - 1;

    return .{
        .prg_rom = prg_rom,
        .prg_rom_mask = prg_rom_mask,
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
