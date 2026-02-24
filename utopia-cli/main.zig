const std = @import("std");
const utopia = @import("utopia");
const cli = @import("./cli.zig");
const logger = @import("./logger.zig");

pub const utopia_logger: utopia.log.Interface = .{
    .enabled = logger.enabled,
    .record = logger.record,
};

pub fn main() !void {
    try logger.init();
    defer logger.deinit();

    const allocator = std.heap.c_allocator;
    const app_args, const device_args = try cli.parse(allocator) orelse return;

    _ = app_args;

    var device = try utopia.Device.init(allocator, device_args);

    defer device.deinit();

    device.runFrame();
}

pub fn panicHandler(msg: []const u8, first_trace_addr: ?usize) noreturn {
    logger.deinit();
    std.debug.defaultPanic(msg, first_trace_addr);
}
