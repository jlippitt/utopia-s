const std = @import("std");
const fw = @import("framework");
const NROM = @import("./Cartridge/NROM.zig");
const UxROM = @import("./Cartridge/UxROM.zig");

const ines_string: []const u8 = &.{ 0x4e, 0x45, 0x53, 0x1a };

const header_size = 16;
const trainer_size = 512;
const prg_rom_multiplier = 16384;
const chr_rom_multiplier = 8192;

const prg_ram_size = 8192;
const prg_ram_mask = prg_ram_size - 1;

const ci_ram_size = 2048;

const prg_page_size = 4096;
const chr_page_size = 1024;

var test_rom_buf: [256]u8 = undefined;
var test_rom_writer = std.fs.File.stderr().writer(&test_rom_buf);

const Self = @This();

prg_read_mapping: [16]PrgMapping = @splat(.open_bus),
prg_write_mapping: [16]PrgMapping = @splat(.open_bus),
prg_rom: []const u8,
prg_rom_mask: u32,
prg_ram: []u8,
vram_address: u15 = 0,
chr_mapping: [8]u32 = @splat(0),
chr_data: []u8,
chr_mask: u32,
chr_writable: bool,
name_mapping: [4]NameMapping,
ci_ram: *[ci_ram_size]u8,
mapper: Mapper,

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

    const chr_data, const chr_mask, const chr_writable = if (chr_rom_size == 0)
        .{
            try arena.allocator().alloc(u8, chr_rom_multiplier),
            chr_rom_multiplier - 1,
            true,
        }
    else
        .{
            @constCast(rom[(prg_rom_begin + prg_rom_size)..][0..chr_rom_size]),
            chr_rom_size - 1,
            false,
        };

    const name_mapping = if (fw.num.bit(rom[6], 0)) blk: {
        fw.log.debug("Default Mirror Mode: Vertical", .{});
        break :blk NameMapping.mirror_vertical;
    } else blk: {
        fw.log.debug("Default Mirror Mode: Horizontal", .{});
        break :blk NameMapping.mirror_horizontal;
    };

    const prg_ram = try arena.allocator().alloc(u8, prg_ram_size);
    const ci_ram = try arena.allocator().alloc(u8, ci_ram_size);

    var self: Self = .{
        .prg_rom = prg_rom,
        .prg_rom_mask = prg_rom_mask,
        .prg_ram = prg_ram,
        .chr_data = chr_data,
        .chr_mask = chr_mask,
        .chr_writable = chr_writable,
        .name_mapping = name_mapping,
        .ci_ram = ci_ram[0..ci_ram_size],
        .mapper = undefined,
    };

    const mapper_number = (rom[7] & 0xf0) | (rom[6] >> 4);

    self.mapper = switch (mapper_number) {
        0 => try NROM.init(arena, &self),
        2 => try UxROM.init(arena, &self),
        else => fw.log.unimplemented("INES mapper: {d}", .{mapper_number}),
    };

    return self;
}

pub fn deinit(self: *Self) void {
    self.mapper.deinit();
}

pub fn readPrg(self: *const Self, address: u16, prev_value: u8) u8 {
    const page = self.prg_read_mapping[@as(u4, @truncate(address >> 12))];

    return switch (page) {
        .rom => |offset| self.prg_rom[offset | (address & 0x0fff)],
        .ram => |offset| self.prg_ram[offset | (address & 0x0fff)],
        .register => fw.log.todo("Mapper register reads", .{}),
        .open_bus => prev_value,
    };
}

pub fn writePrg(self: *Self, address: u16, value: u8) void {
    const page = self.prg_write_mapping[@as(u4, @truncate(address >> 12))];

    return switch (page) {
        .rom => fw.log.warn("Write to PRG ROM area: {X:04} <= {X:02}", .{ address, value }),
        .ram => |offset| self.prg_ram[offset | (address & 0x0fff)] = value,
        .register => self.mapper.writeRegister(self, address, value),
        .open_bus => {},
    };
}

pub fn setVramAddress(self: *Self, address: u15) void {
    self.vram_address = address;
}

pub fn readVram(self: *Self) u8 {
    if ((self.vram_address & 0x2000) == 0) {
        const offset = self.chr_mapping[@as(u3, @truncate(self.vram_address >> 10))];
        return self.chr_data[offset | (self.vram_address & 0x03ff)];
    }

    return switch (self.name_mapping[@as(u2, @truncate(self.vram_address >> 10))]) {
        .ci_ram => |offset| self.ci_ram[offset | @as(u10, @truncate(self.vram_address))],
        .custom => fw.log.todo("Custom nametable mappings", .{}),
    };
}

pub fn writeVram(self: *Self, value: u8) void {
    if ((self.vram_address & 0x2000) == 0) {
        if (self.chr_writable) {
            const offset = self.chr_mapping[@as(u3, @truncate(self.vram_address >> 10))];
            self.chr_data[offset | (self.vram_address & 0x03ff)] = value;
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

pub fn mapPrgRom(self: *Self, start: u32, len: u32, page_offset: i32) void {
    var offset: u32 = if (page_offset >= 0)
        @as(u32, @intCast(page_offset)) * prg_page_size
    else
        @as(u32, @intCast(self.prg_rom.len)) - (@as(u32, @intCast(-page_offset)) * prg_page_size);

    for (start..(start + len)) |index| {
        self.prg_read_mapping[index] = .{ .rom = offset & self.prg_rom_mask };
        offset += prg_page_size;
    }
}

pub fn mapPrgRam(self: *Self, start: u32, len: u32, page_offset: i32) void {
    var offset: u32 = if (page_offset >= 0)
        @as(u32, @intCast(page_offset)) * prg_page_size
    else
        @as(u32, @intCast(self.prg_ram.len)) - (@as(u32, @intCast(-page_offset)) * prg_page_size);

    for (start..(start + len)) |index| {
        self.prg_read_mapping[index] = .{ .ram = offset & prg_ram_mask };
        self.prg_write_mapping[index] = .{ .ram = offset & prg_ram_mask };
        offset += prg_page_size;
    }
}

pub fn mapPrgRegisterWrite(self: *Self, start: u32, len: u32) void {
    for (start..(start + len)) |index| {
        self.prg_write_mapping[index] = .register;
    }
}

pub fn mapChr(self: *Self, start: u32, len: u32, page_offset: i32) void {
    var offset: u32 = if (page_offset >= 0)
        @as(u32, @intCast(page_offset)) * chr_page_size
    else
        @as(u32, @intCast(self.chr_data.len)) - (@as(u32, @intCast(-page_offset)) * chr_page_size);

    for (start..(start + len)) |index| {
        self.chr_mapping[index] = offset & self.chr_mask;
        offset += chr_page_size;
    }
}

pub fn printMappings(self: *Self) void {
    fw.log.debug("PRG Read Mapping: {any}", .{self.prg_read_mapping});
    fw.log.debug("PRG Write Mapping: {any}", .{self.prg_write_mapping});
    fw.log.debug("CHR Mapping: {any}", .{self.chr_mapping});
    fw.log.debug("Name Mapping: {any}", .{self.name_mapping});
}

pub const PrgMapping = union(enum) {
    rom: u32,
    ram: u32,
    register: void,
    open_bus: void,
};

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
                fw.log.panic("Register write not implemented for this mapper", .{});
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
