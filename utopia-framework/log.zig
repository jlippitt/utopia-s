const std = @import("std");
const root = @import("root");

pub const Level = enum {
    err,
    warn,
    info,
    debug,
    trace,
};

pub const Interface = struct {
    enabled: *const fn (comptime level: Level) bool,
    record: *const fn (comptime level: Level, comptime fmt: []const u8, args: anytype) void,
};

const null_logger = struct {
    const interface: Interface = .{
        .enabled = enabled,
        .record = record,
    };

    fn enabled(comptime level: Level) bool {
        _ = level;
        return false;
    }

    fn record(comptime level: Level, comptime fmt: []const u8, args: anytype) void {
        _ = level;
        _ = fmt;
        _ = args;
    }
};

const logger: Interface = if (@hasDecl(root, "utopia_logger"))
    root.utopia_logger
else
    null_logger.interface;

pub fn log(comptime level: Level, comptime fmt: []const u8, args: anytype) void {
    if (!comptime logger.enabled(level)) {
        return;
    }

    logger.record(level, fmt, args);
}

pub fn err(comptime fmt: []const u8, args: anytype) void {
    log(.err, fmt, args);
}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    log(.warn, fmt, args);
}

pub fn info(comptime fmt: []const u8, args: anytype) void {
    log(.info, fmt, args);
}

pub fn debug(comptime fmt: []const u8, args: anytype) void {
    log(.debug, fmt, args);
}

pub fn trace(comptime fmt: []const u8, args: anytype) void {
    log(.trace, fmt, args);
}

pub fn panic(comptime fmt: []const u8, args: anytype) void {
    std.debug.panic(fmt, args);
}

pub fn todo(comptime fmt: []const u8, args: anytype) void {
    panic("TODO: ", fmt, args);
}

pub fn unimplemented(comptime fmt: []const u8, args: anytype) void {
    panic("Unimplemented: " ++ fmt, args);
}
