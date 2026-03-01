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
    pushContext: *const fn (name: []const u8) void,
    popContext: *const fn () void,
};

const null_logger = struct {
    fn enabled(comptime level: Level) bool {
        _ = level;
        return false;
    }

    fn record(comptime level: Level, comptime fmt: []const u8, args: anytype) void {
        _ = level;
        _ = fmt;
        _ = args;
    }

    fn pushContext(name: []const u8) void {
        _ = name;
    }

    fn popContext() void {}
};

const logger: Interface = if (@hasDecl(root, "utopia_logger"))
    root.utopia_logger
else
    .{
        .enabled = null_logger.enabled,
        .record = null_logger.record,
        .pushContext = null_logger.pushContext,
        .popContext = null_logger.popContext,
    };

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

pub fn panic(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.panic(fmt, args);
}

pub fn todo(comptime fmt: []const u8, args: anytype) noreturn {
    panic("TODO: " ++ fmt, args);
}

pub fn unimplemented(comptime fmt: []const u8, args: anytype) noreturn {
    panic("Unimplemented: " ++ fmt, args);
}

pub fn pushContext(name: []const u8) void {
    logger.pushContext(name);
}

pub fn popContext() void {
    logger.popContext();
}
