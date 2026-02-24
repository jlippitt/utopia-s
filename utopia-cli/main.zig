const std = @import("std");
const utopia = @import("utopia");
const cli = @import("./cli.zig");

pub fn main() !void {
    const allocator = std.heap.c_allocator;
    const app_args, const device_args = try cli.parse(allocator) orelse return;

    _ = app_args;

    var error_buf: [256]u8 = undefined;
    var stderr = std.fs.File.stderr().writer(&error_buf);

    const default_args: utopia.DefaultArgs = .{
        .allocator = allocator,
        .error_writer = &stderr.interface,
    };

    var device = utopia.Device.init(default_args, device_args) catch |err| {
        stderr.interface.flush() catch {};
        return err;
    };

    defer device.deinit();

    device.runFrame();
}
