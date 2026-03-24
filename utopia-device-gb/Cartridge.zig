const std = @import("std");
const fw = @import("framework");
const RomOnly = @import("./Cartridge/RomOnly.zig");
const MBC1 = @import("./Cartridge/MBC1.zig");

const rom_page_size = 16384;
const ram_page_size = 8192;

const Self = @This();

rom_mapping: [2]u32 = @splat(0),
rom: []const u8,
rom_mask: u32,
ram_mapping: ?u32 = null,
ram: []u8,
ram_mask: u32,
mapper: Mapper,

pub fn init(arena: *std.heap.ArenaAllocator, rom: []const u8) error{OutOfMemory}!Self {
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

    const rom_size = rom.len; // TODO: Validate this against header
    std.debug.assert(std.math.isPowerOfTwo(rom_size));

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

    const ram = try arena.allocator().alloc(u8, ram_size);

    var self: Self = .{
        .rom = rom,
        .rom_mask = @as(u32, @intCast(rom_size)) - 1,
        .ram = ram,
        .ram_mask = if (ram_size > 0) ram_size - 1 else 0,
        .mapper = undefined,
    };

    self.mapper = switch (cartridge_type.mapper) {
        .rom => try RomOnly.init(arena, &self),
        .mbc1 => try MBC1.init(arena, &self),
        else => fw.log.panic("Unsupported mapper type: {t}", .{cartridge_type.mapper}),
    };

    return self;
}

pub fn readRom(self: *const Self, address: u16) u8 {
    const offset = self.rom_mapping[@as(u1, @truncate(address >> 14))];
    return self.rom[offset | (address & 0x3fff)];
}

pub fn writeRegister(self: *Self, address: u16, value: u8) void {
    return self.mapper.writeRegister(self, address, value);
}

pub fn readRam(self: *const Self, address: u16) u8 {
    if (self.ram_mapping) |offset| {
        return self.ram[offset | (address & 0x1fff)];
    }

    return 0xff;
}

pub fn writeRam(self: *Self, address: u16, value: u8) void {
    if (self.ram_mapping) |offset| {
        self.ram[offset | (address & 0x1fff)] = value;
    }
}

pub fn mapRom(self: *Self, index: u1, page_offset: u32) void {
    self.rom_mapping[index] = (page_offset * rom_page_size) & self.rom_mask;
}

pub fn mapRam(self: *Self, page_offset: u32) void {
    self.ram_mapping = if (self.ram.len > 0)
        (page_offset * ram_page_size) & self.ram_mask
    else
        null;
}

pub fn unmapRam(self: *Self) void {
    self.ram_mapping = null;
}

pub fn printMappings(self: *Self) void {
    fw.log.debug("ROM Mapping: {any}", .{self.rom_mapping});
    fw.log.debug("RAM Mapping: {any}", .{self.ram_mapping});
}

pub const Mapper = struct {
    pub fn Interface(comptime T: type) type {
        const defaults = struct {
            fn deinit(self: *T) void {
                _ = self;
            }

            fn writeRegister(self: *T, cartridge: *Self, address: u16, value: u8) void {
                _ = self;
                _ = cartridge;
                _ = address;
                _ = value;
                fw.log.warn("Register write not implemented for this mapper", .{});
            }
        };

        return struct {
            deinit: *const fn (self: *T) void = defaults.deinit,
            writeRegister: *const fn (
                self: *T,
                cartridge: *Self,
                address: u16,
                value: u8,
            ) void = defaults.writeRegister,
        };
    }

    ptr: *anyopaque,
    vtable: *const Interface(anyopaque),

    pub fn init(
        inner: anytype,
        comptime iface: Interface(@typeInfo(@TypeOf(inner)).pointer.child),
    ) @This() {
        const T = @typeInfo(@TypeOf(inner)).pointer.child;

        const gen = struct {
            fn deinitImpl(ptr: *anyopaque) void {
                const self: *T = @ptrCast(@alignCast(ptr));
                return @call(.always_inline, iface.deinit, .{self});
            }

            fn writeRegisterImpl(
                ptr: *anyopaque,
                cartridge: *Self,
                address: u16,
                value: u8,
            ) void {
                const self: *T = @ptrCast(@alignCast(ptr));
                return @call(.always_inline, iface.writeRegister, .{
                    self,
                    cartridge,
                    address,
                    value,
                });
            }

            const vtable = Interface(anyopaque){
                .deinit = deinitImpl,
                .writeRegister = writeRegisterImpl,
            };
        };

        return .{
            .ptr = inner,
            .vtable = &gen.vtable,
        };
    }

    pub fn deinit(self: @This()) void {
        return self.vtable.deinit(self.ptr);
    }

    pub fn writeRegister(self: @This(), cartridge: *Self, address: u16, value: u8) void {
        return self.vtable.writeRegister(self.ptr, cartridge, address, value);
    }
};

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

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.writeAll(switch (self) {
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
    }
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
        try self.mapper.format(writer);

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
