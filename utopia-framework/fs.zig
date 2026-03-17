const std = @import("std");
const log = @import("./log.zig");

const max_file_size = 1024 * 1024 * 1024; // 1GiB

pub const ReadAllocError = std.mem.Allocator.Error || std.fs.File.OpenError || std.fs.File.ReadError;

pub fn readFileAlloc(
    allocator: std.mem.Allocator,
    path: []const u8,
) ReadAllocError![]u8 {
    return std.fs.cwd().readFileAlloc(
        allocator,
        path,
        max_file_size,
    ) catch |err| {
        log.err("Failed to read file '{s}': {t}", .{ path, err });
        return err;
    };
}

pub fn readFileAllocAligned(
    allocator: std.mem.Allocator,
    path: []const u8,
    comptime alignment: std.mem.Alignment,
) ReadAllocError![]align(alignment.toByteUnits()) u8 {
    return std.fs.cwd().readFileAllocOptions(
        allocator,
        path,
        max_file_size,
        null,
        alignment,
        null,
    ) catch |err| {
        log.err("Failed to read file '{s}': {t}", .{ path, err });
        return err;
    };
}
