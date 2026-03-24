const std = @import("std");
const fw = @import("framework");
const Self = @This();

rom: []const u8,

pub fn init(rom: []const u8) Self {
    fw.log.debug("Title: {s}", .{std.mem.sliceTo(rom[0x134..0x144], 0)});

    const mapper_byte = rom[0x147];

    const cartridge_type: CartridgeType = switch (mapper_byte) {
        0x00 => .{ .mapper = .rom },
        0x01 => .{ .mapper = .mbc1 },
        0x02 => .{ .mapper = .mbc1, .ram = true },
        0x03 => .{ .mapper = .mbc1, .ram = true, .battery = true },
        0x05 => .{ .mapper = .mbc2 },
        0x06 => .{ .mapper = .mbc2, .battery = true },
        0x08 => .{ .mapper = .rom, .ram = true },
        0x09 => .{ .mapper = .rom, .ram = true, .battery = true },
        0x0b => .{ .mapper = .mmm01 },
        0x0c => .{ .mapper = .mmm01, .ram = true },
        0x0d => .{ .mapper = .mmm01, .timer = true, .battery = true },
        0x10 => .{ .mapper = .mbc3, .timer = true, .ram = true, .battery = true },
        0x11 => .{ .mapper = .mbc3 },
        0x12 => .{ .mapper = .mbc3, .ram = true },
        0x13 => .{ .mapper = .mbc3, .ram = true, .battery = true },
        0x19 => .{ .mapper = .mbc5 },
        0x1a => .{ .mapper = .mbc5, .ram = true },
        0x1b => .{ .mapper = .mbc5, .ram = true, .battery = true },
        0x1c => .{ .mapper = .mbc5, .rumble = true },
        0x1d => .{ .mapper = .mbc5, .rumble = true, .ram = true },
        0x1e => .{ .mapper = .mbc5, .rumble = true, .ram = true, .battery = true },
        0x20 => .{ .mapper = .mbc6 },
        0x21 => .{ .mapper = .mbc7, .sensor = true, .rumble = true, .ram = true, .battery = true },
        0xfc => .{ .mapper = .camera },
        0xfd => .{ .mapper = .tama5 },
        0xfe => .{ .mapper = .huc3 },
        0xff => .{ .mapper = .huc1, .ram = true, .battery = true },
        else => fw.log.panic("Invalid Cartridge Type: {X:02}", .{mapper_byte}),
    };

    fw.log.debug("Cartridge Type: {X:02} ({f})", .{ mapper_byte, cartridge_type });

    const ram_size: u32 = switch (rom[0x149]) {
        0 => 0,
        2 => 8192,
        3 => 32768,
        4 => 131072,
        5 => 65536,
        else => |byte| blk: {
            fw.log.warn("Invalid RAM size specifier: {X:02}", .{byte});
            break :blk 0;
        },
    };

    fw.log.debug("RAM Size: {d}", .{ram_size});

    return .{
        .rom = rom,
    };
}

pub fn readRom(self: *const Self, address: u16) u8 {
    return self.rom[address];
}

const MapperType = enum {
    rom,
    mbc1,
    mbc2,
    mbc3,
    mbc5,
    mbc6,
    mbc7,
    mmm01,
    camera,
    tama5,
    huc1,
    huc3,
};

const CartridgeType = struct {
    mapper: MapperType,
    timer: bool = false,
    sensor: bool = false,
    rumble: bool = false,
    ram: bool = false,
    battery: bool = false,

    pub fn format(
        self: *const @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.writeAll(switch (self.mapper) {
            .rom => "ROM",
            .mbc1 => "MBC1",
            .mbc2 => "MBC2",
            .mbc3 => "MBC3",
            .mbc5 => "MBC5",
            .mbc6 => "MBC6",
            .mbc7 => "MBC7",
            .mmm01 => "MMM01",
            .camera => "Camera",
            .tama5 => "TAMA5",
            .huc1 => "HUC1",
            .huc3 => "HUC3",
        });

        if (self.timer) {
            try writer.writeAll("+Timer");
        }

        if (self.sensor) {
            try writer.writeAll("+Sensor");
        }

        if (self.rumble) {
            try writer.writeAll("+Rumble");
        }

        if (self.ram) {
            try writer.writeAll("+RAM");
        }

        if (self.battery) {
            try writer.writeAll("+Battery");
        }
    }
};
