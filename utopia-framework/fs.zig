const std = @import("std");

const max_file_size = 1024 * 1024 * 1024; // 1GiB

pub const ReadAllocAlignedError = std.mem.Allocator.Error || std.fs.File.OpenError || std.fs.File.ReadError;

pub fn readFileAllocAligned(
    allocator: std.mem.Allocator,
    path: []const u8,
    comptime alignment: std.mem.Alignment,
    error_writer: ?*std.Io.Writer,
) ReadAllocAlignedError![]align(alignment.toByteUnits()) u8 {
    return std.fs.cwd().readFileAllocOptions(
        allocator,
        path,
        max_file_size,
        null,
        alignment,
        null,
    ) catch |err| {
        if (error_writer) |writer| {
            writer.print("Failed to read file '{s}': {t}\n", .{ path, err }) catch {};
        }

        return err;
    };
}
