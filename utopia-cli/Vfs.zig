const std = @import("std");
const utopia = @import("utopia");

const max_file_size = 1024 * 1024 * 1024; // 1GiB

const Self = @This();

rom_path: []const u8,
bios_path: []const u8,
save_path: []const u8,

pub fn init(
    allocator: std.mem.Allocator,
    rom_path: []const u8,
    bios_path: ?[]const u8,
    save_path: ?[]const u8,
) error{OutOfMemory}!utopia.Vfs {
    const self = try allocator.create(Self);

    self.* = .{
        .rom_path = rom_path,
        .bios_path = bios_path orelse std.fs.path.dirname(rom_path) orelse "",
        .save_path = save_path orelse std.fs.path.dirname(rom_path) orelse "",
    };

    return .init(self, .{
        .deinit = deinit,
        .readRom = readRom,
        .readBios = readBios,
        .readSave = readSave,
        .writeSave = writeSave,
    });
}

fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    allocator.destroy(self);
}

fn readRom(
    self: *Self,
    allocator: std.mem.Allocator,
    alignment: std.mem.Alignment,
) utopia.Vfs.Error![]u8 {
    return readFileAlloc(allocator, self.rom_path, alignment);
}

fn readBios(
    self: *Self,
    allocator: std.mem.Allocator,
    file_path: []const u8,
    alignment: std.mem.Alignment,
) utopia.Vfs.Error![]u8 {
    const path = try std.fs.path.join(allocator, &.{ self.bios_path, file_path });
    defer allocator.free(path);
    return readFileAlloc(allocator, path, alignment);
}

pub fn readSave(
    self: *Self,
    allocator: std.mem.Allocator,
    save_type: ?[]const u8,
    data: []u8,
) utopia.Vfs.Error!void {
    const path = try self.getSaveFilePath(allocator, save_type);
    defer allocator.free(path);

    _ = std.fs.cwd().readFile(path, data) catch |err| switch (err) {
        error.FileNotFound => {},
        else => {
            utopia.log.err("Failed to read file '{s}': {t}", .{ path, err });
            return error.VfsError;
        },
    };
}

pub fn writeSave(
    self: *Self,
    allocator: std.mem.Allocator,
    save_type: ?[]const u8,
    data: []const u8,
) utopia.Vfs.Error!void {
    const path = try self.getSaveFilePath(allocator, save_type);
    defer allocator.free(path);

    std.fs.cwd().writeFile(.{
        .sub_path = path,
        .data = data,
    }) catch |err| {
        utopia.log.err("Failed to write file '{s}': {t}", .{ path, err });
        return error.VfsError;
    };
}

fn getSaveFilePath(
    self: *const Self,
    allocator: std.mem.Allocator,
    save_type: ?[]const u8,
) error{OutOfMemory}![]const u8 {
    const file_name = try if (save_type) |some_save_type|
        std.fmt.allocPrint(allocator, "{s}.{s}.sav", .{
            std.fs.path.stem(self.rom_path),
            some_save_type,
        })
    else
        std.fmt.allocPrint(allocator, "{s}.sav", .{
            std.fs.path.stem(self.rom_path),
        });
    defer allocator.free(file_name);

    return try std.fs.path.join(allocator, &.{
        self.save_path,
        file_name,
    });
}

fn readFileAlloc(
    allocator: std.mem.Allocator,
    path: []const u8,
    alignment: std.mem.Alignment,
) utopia.Vfs.Error![]u8 {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        utopia.log.err("Failed to open file '{s}': {t}", .{ path, err });
        return error.VfsError;
    };
    defer file.close();

    const size = file.getEndPos() catch |err| {
        utopia.log.err("Failed to determine size of file '{s}': {t}", .{ path, err });
        return error.VfsError;
    };

    const ptr = allocator.rawAlloc(size, alignment, @returnAddress()) orelse {
        return error.OutOfMemory;
    };

    const data = ptr[0..size];

    const bytes_read = file.readAll(data) catch |err| {
        utopia.log.err("Failed to read file '{s}': {t}", .{ path, err });
        return error.VfsError;
    };

    std.debug.assert(bytes_read == size);

    return data;
}
