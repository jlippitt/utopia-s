const std = @import("std");
const utopia = @import("utopia");
const cli = @import("./cli.zig");

pub fn main() !void {
    const allocator = std.heap.c_allocator;
    const app_args, const device_args = try cli.parse(allocator) orelse return;

    _ = app_args;

    var device = try utopia.Device.init(.{ .allocator = allocator }, device_args);
    defer device.deinit();

    device.runFrame();
}
