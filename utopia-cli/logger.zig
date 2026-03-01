const builtin = @import("builtin");
const std = @import("std");
const options = @import("options");
const utopia = @import("utopia");

const max_files = 4;
const max_depth = 4;
const buffer_size = 65536;
const log_path = "./log";

pub const default_level: utopia.log.Level = switch (builtin.mode) {
    .Debug => .debug,
    .ReleaseSafe => .info,
    .ReleaseFast, .ReleaseSmall => .err,
};

const max_level: utopia.log.Level = if (options.log_level) |level_string|
    @field(utopia.log.Level, level_string)
else
    default_level;

const File = struct {
    handle: std.fs.File,
    writer: std.fs.File.Writer,
    buffer: [buffer_size]u8,
};

threadlocal var files: std.ArrayListUnmanaged(File) = .empty;
threadlocal var span_map: std.StringHashMapUnmanaged(*std.fs.File.Writer) = .empty;
threadlocal var stack: std.ArrayListUnmanaged(*std.fs.File.Writer) = .empty;

pub fn init(allocator: std.mem.Allocator) !void {
    if (comptime @intFromEnum(max_level) < @intFromEnum(utopia.log.Level.debug)) {
        return;
    }

    try std.fs.cwd().makePath(log_path);

    try files.ensureTotalCapacity(allocator, max_files);
    try span_map.ensureTotalCapacity(allocator, max_files);
    try stack.ensureTotalCapacity(allocator, max_files);

    stack.appendAssumeCapacity(try createLogFile("main"));
}

pub fn deinit() void {
    if (comptime @intFromEnum(max_level) <= @intFromEnum(utopia.log.Level.info)) {
        return;
    }

    for (files.items) |*file| {
        file.writer.interface.flush() catch {};
        file.handle.close();
    }

    stack.clearRetainingCapacity();
    span_map.clearRetainingCapacity();
    files.clearRetainingCapacity();
}

pub fn enabled(comptime level: utopia.log.Level) bool {
    return @intFromEnum(level) <= @intFromEnum(max_level);
}

pub fn record(comptime level: utopia.log.Level, comptime fmt: []const u8, args: anytype) void {
    if (comptime @intFromEnum(level) <= @intFromEnum(utopia.log.Level.info)) {
        std.debug.print(fmt ++ "\n", args);
    }

    if (comptime @intFromEnum(max_level) <= @intFromEnum(utopia.log.Level.info)) {
        return;
    }

    stack.getLast().interface.print(fmt ++ "\n", args) catch {};
}

pub fn pushContext(name: []const u8) void {
    if (comptime @intFromEnum(max_level) <= @intFromEnum(utopia.log.Level.info)) {
        return;
    }

    stack.appendAssumeCapacity(span_map.get(name) orelse createLogFile(name) catch |err| {
        std.debug.panic("Failed to create log file '{s}': {t}", .{ name, err });
    });
}

pub fn popContext() void {
    if (comptime @intFromEnum(max_level) <= @intFromEnum(utopia.log.Level.info)) {
        return;
    }

    _ = stack.pop() orelse {
        std.debug.panic("Called 'popContext' with empty context stack", .{});
    };
}

fn createLogFile(name: []const u8) !*std.fs.File.Writer {
    var path_buf: [256]u8 = undefined;

    const path = try std.fmt.bufPrint(&path_buf, "{s}/{s}.log", .{
        log_path,
        name,
    });

    const file = files.addOneAssumeCapacity();
    file.handle = try std.fs.cwd().createFile(path, .{});
    file.writer = file.handle.writer(&file.buffer);

    span_map.putAssumeCapacity(name, &file.writer);

    return &file.writer;
}
