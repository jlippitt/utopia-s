const std = @import("std");
const sdl3 = @import("sdl3");
const utopia = @import("utopia");
const cli = @import("./cli.zig");
const logger = @import("./logger.zig");

pub const panic = std.debug.FullPanic(panicHandler);

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

    try sdl3.init(.everything);
    defer sdl3.quit(.everything);

    var device = try device_args.initDevice(allocator);
    defer device.deinit();

    const size = device.getScreenSize();

    const window = try sdl3.video.Window.init("Utopia-S", size.x, size.y, .{});
    defer window.deinit();

    try window.setPosition(.{ .centered = null }, .{ .centered = null });

    const renderer = try sdl3.render.Renderer.init(window, null);
    defer renderer.deinit();

    const texture = try renderer.createTexture(
        .packed_xbgr_8_8_8_8,
        .streaming,
        size.x,
        size.y,
    );
    defer texture.deinit();

    outer: while (true) {
        while (sdl3.events.poll()) |event| {
            switch (event) {
                .quit => break :outer,
                .key_down => |key| if (key.scancode) |scancode| {
                    switch (scancode) {
                        .escape => break :outer,
                        else => {},
                    }
                },
                else => {},
            }
        }

        device.runFrame();

        try texture.update(null, device.getPixels().ptr, size.x * 4);
        try renderer.renderTexture(texture, null, null);
        try renderer.present();
    }
}

fn panicHandler(msg: []const u8, first_trace_addr: ?usize) noreturn {
    logger.deinit();
    std.debug.defaultPanic(msg, first_trace_addr);
}
