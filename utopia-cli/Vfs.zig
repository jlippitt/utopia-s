const std = @import("std");
const utopia = @import("utopia");

const max_file_size = 1024 * 1024 * 1024; // 1GiB

pub const Error = std.mem.Allocator.Error || std.fs.File.OpenError || std.fs.File.ReadError;

const Self = @This();

rom_path: []const u8,
bios_path: []const u8,

pub fn init(rom_path: []const u8, bios_path: ?[]const u8) Self {
    return .{
        .rom_path = rom_path,
        .bios_path = bios_path orelse std.fs.path.dirname(rom_path) orelse "",
    };
}

pub fn readRom(self: *const Self, arena: *std.heap.ArenaAllocator) Error![]u8 {
    return readFile(arena, self.rom_path);
}

pub fn readRomAligned(
    self: *const Self,
    arena: *std.heap.ArenaAllocator,
    comptime alignment: std.mem.Alignment,
) Error![]align(alignment.toByteUnits()) u8 {
    return readFileAligned(arena, self.rom_path, alignment);
}

pub fn readBios(self: *const Self, arena: *std.heap.ArenaAllocator, file_path: []const u8) Error![]u8 {
    const path = try std.fs.path.join(arena.child_allocator, &.{ self.bios_path, file_path });
    defer arena.child_allocator.free(path);
    return readFile(arena, path);
}

pub fn readBiosAligned(
    self: *const Self,
    arena: *std.heap.ArenaAllocator,
    file_path: []const u8,
    comptime alignment: std.mem.Alignment,
) Error![]align(alignment.toByteUnits()) u8 {
    const path = try std.fs.path.join(arena.child_allocator, &.{ self.bios_path, file_path });
    defer arena.child_allocator.free(path);
    return readFileAligned(arena, path, alignment);
}

fn readFile(
    arena: *std.heap.ArenaAllocator,
    path: []const u8,
) Error![]u8 {
    return std.fs.cwd().readFileAlloc(
        arena.allocator(),
        path,
        max_file_size,
    ) catch |err| {
        utopia.log.err("Failed to read file '{s}': {t}", .{ path, err });
        return err;
    };
}

fn readFileAligned(
    arena: *std.heap.ArenaAllocator,
    path: []const u8,
    comptime alignment: std.mem.Alignment,
) Error![]align(alignment.toByteUnits()) u8 {
    return std.fs.cwd().readFileAllocOptions(
        arena.allocator(),
        path,
        max_file_size,
        null,
        alignment,
        null,
    ) catch |err| {
        utopia.log.err("Failed to read file '{s}': {t}", .{ path, err });
        return err;
    };
}
