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
    handle: std.Io.File,
    writer: std.Io.File.Writer,
    buffer: [buffer_size]u8,
};

const Logger = struct {
    io: std.Io,
    files: std.ArrayList(File),
    span_map: std.StringHashMapUnmanaged(*std.Io.File.Writer),
    stack: std.ArrayList(*std.Io.File.Writer),
};

threadlocal var logger: Logger = undefined;

pub fn init(io: std.Io, allocator: std.mem.Allocator) !void {
    if (comptime @intFromEnum(max_level) < @intFromEnum(utopia.log.Level.debug)) {
        return;
    }

    logger = .{
        .io = io,
        .files = .empty,
        .span_map = .empty,
        .stack = .empty,
    };

    try std.Io.Dir.cwd().createDirPath(io, log_path);

    try logger.files.ensureTotalCapacity(allocator, max_files);
    try logger.span_map.ensureTotalCapacity(allocator, max_files);
    try logger.stack.ensureTotalCapacity(allocator, max_files);

    logger.stack.appendAssumeCapacity(try createLogFile("main"));
}

pub fn deinit() void {
    if (comptime @intFromEnum(max_level) <= @intFromEnum(utopia.log.Level.info)) {
        return;
    }

    for (logger.files.items) |*file| {
        file.writer.interface.flush() catch {};
        file.handle.close(logger.io);
    }

    logger.stack.clearRetainingCapacity();
    logger.span_map.clearRetainingCapacity();
    logger.files.clearRetainingCapacity();
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

    logger.stack.getLast().interface.print(fmt ++ "\n", args) catch {};
}

pub fn pushContext(name: []const u8) void {
    if (comptime @intFromEnum(max_level) <= @intFromEnum(utopia.log.Level.info)) {
        return;
    }

    logger.stack.appendAssumeCapacity(logger.span_map.get(name) orelse createLogFile(name) catch |err| {
        std.debug.panic("Failed to create log file '{s}': {t}", .{ name, err });
    });
}

pub fn popContext() void {
    if (comptime @intFromEnum(max_level) <= @intFromEnum(utopia.log.Level.info)) {
        return;
    }

    _ = logger.stack.pop() orelse {
        std.debug.panic("Called 'popContext' with empty context stack", .{});
    };
}

fn createLogFile(name: []const u8) !*std.Io.File.Writer {
    var path_buf: [256]u8 = undefined;

    const path = try std.fmt.bufPrint(&path_buf, "{s}/{s}.log", .{
        log_path,
        name,
    });

    const file = logger.files.addOneAssumeCapacity();
    file.handle = try std.Io.Dir.cwd().createFile(logger.io, path, .{});
    file.writer = file.handle.writer(logger.io, &file.buffer);

    logger.span_map.putAssumeCapacity(name, &file.writer);

    return &file.writer;
}
