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

    var src_size = device.getScreenSize();
    var dst_size = try getBestSize(src_size, null);

    const window = try sdl3.video.Window.init("Utopia-S", dst_size.x, dst_size.y, .{});
    defer window.deinit();

    try window.setPosition(.{ .centered = null }, .{ .centered = null });

    const renderer = try sdl3.render.Renderer.init(window, null);
    defer renderer.deinit();

    var texture = try renderer.createTexture(
        .packed_xbgr_8_8_8_8,
        .streaming,
        src_size.x,
        src_size.y,
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

        const new_size = device.getScreenSize();

        if (new_size.x != src_size.x or new_size.y != src_size.y) {
            const display = try window.getDisplayForWindow();

            src_size = new_size;
            dst_size = try getBestSize(src_size, display);

            try window.setSize(dst_size.x, dst_size.y);
            try window.setPosition(.{ .centered = display }, .{ .centered = display });

            texture.deinit();

            texture = try renderer.createTexture(
                .packed_xbgr_8_8_8_8,
                .streaming,
                src_size.x,
                src_size.y,
            );
        }

        try texture.update(null, device.getPixels().ptr, src_size.x * 4);
        try renderer.renderTexture(texture, null, null);
        try renderer.present();
    }
}

fn panicHandler(msg: []const u8, first_trace_addr: ?usize) noreturn {
    logger.deinit();
    std.debug.defaultPanic(msg, first_trace_addr);
}

fn getBestSize(
    min_size: utopia.ScreenSize,
    active_display: ?sdl3.video.Display,
) !utopia.ScreenSize {
    const display = active_display orelse (try sdl3.video.getDisplays())[0];
    const bounds = try display.getUsableBounds();

    const max_size: utopia.ScreenSize = .{
        .x = @intCast(bounds.w),
        .y = @intCast(bounds.h),
    };

    const x_scale = max_size.x / min_size.x;
    const y_scale = max_size.y / min_size.y;
    const scale = @min(x_scale, y_scale);

    return .{
        .x = min_size.x * scale,
        .y = min_size.y * scale,
    };
}
