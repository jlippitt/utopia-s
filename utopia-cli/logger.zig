const builtin = @import("builtin");
const std = @import("std");
const options = @import("options");
const utopia = @import("utopia");

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

var file: std.fs.File = undefined;
var writer: std.fs.File.Writer = undefined;
var buffer: [65536]u8 = undefined;

pub fn init() !void {
    try std.fs.cwd().makePath(log_path);
    file = try std.fs.cwd().createFile(log_path ++ "/main.log", .{});
    writer = file.writer(&buffer);
}

pub fn deinit() void {
    writer.interface.flush() catch {};
    file.close();
}

pub fn enabled(comptime level: utopia.log.Level) bool {
    return @intFromEnum(level) <= @intFromEnum(max_level);
}

pub fn record(comptime level: utopia.log.Level, comptime fmt: []const u8, args: anytype) void {
    if (@intFromEnum(level) <= @intFromEnum(utopia.log.Level.info)) {
        std.debug.print(fmt ++ "\n", args);
    }

    writer.interface.print(fmt ++ "\n", args) catch {};
}
