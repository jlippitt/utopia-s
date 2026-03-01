const std = @import("std");
const sdl3 = @import("sdl3");
const utopia = @import("utopia");
const cli = @import("./cli.zig");
const FpsCounter = @import("./FpsCounter.zig");
const logger = @import("./logger.zig");

pub const panic = std.debug.FullPanic(panicHandler);

pub const utopia_logger: utopia.log.Interface = .{
    .enabled = logger.enabled,
    .record = logger.record,
    .pushContext = logger.pushContext,
    .popContext = logger.popContext,
};

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    logger.init(allocator) catch |err| {
        std.debug.panic("Failed to initialize logger: {t}", .{err});
    };
    defer logger.deinit();

    const app_args, const device_args = try cli.parse(allocator) orelse return;

    _ = app_args;

    try sdl3.init(.everything);
    defer sdl3.quit(.everything);

    const app_name = "Utopia-S";

    var device = try device_args.initDevice(allocator);
    defer device.deinit();

    var src_size = device.getScreenSize();

    const init_size = try getBestSize(src_size, null);

    const window = try sdl3.video.Window.init(app_name, init_size.x, init_size.y, .{});
    defer window.deinit();

    const renderer = try sdl3.render.Renderer.init(window, null);
    defer renderer.deinit();

    var texture = try resizeWindow(window, renderer, src_size);
    defer texture.deinit();

    const gamepad_ids = try sdl3.gamepad.getGamepads();

    const gamepad: ?sdl3.gamepad.Gamepad = if (gamepad_ids.len > 0)
        try sdl3.gamepad.Gamepad.init(gamepad_ids[0])
    else
        null;

    defer if (gamepad) |pad| pad.deinit();

    var fps_counter = try FpsCounter.init();
    var controller_state: utopia.ControllerState = .{};

    outer: while (true) {
        while (sdl3.events.poll()) |event| {
            switch (event) {
                .quit => break :outer,
                .window_display_changed => {
                    texture.deinit();
                    texture = try resizeWindow(window, renderer, src_size);
                },
                .key_down => |key| if (key.scancode) |scancode| {
                    switch (scancode) {
                        .escape => break :outer,
                        else => {},
                    }
                },
                .gamepad_button_down => |button| switch (button.button) {
                    inline else => |field| @field(controller_state.button, @tagName(field)) = true,
                },
                .gamepad_button_up => |button| switch (button.button) {
                    inline else => |field| @field(controller_state.button, @tagName(field)) = false,
                },
                .gamepad_axis_motion => |axis| switch (axis.axis) {
                    inline else => |field| @field(controller_state.axis, @tagName(field)) =
                        @as(f32, @floatFromInt(axis.value)) /
                        (std.math.maxInt(@TypeOf(axis.value)) + 1),
                },
                else => {},
            }
        }

        device.updateControllerState(&controller_state);
        device.runFrame();

        const new_size = device.getScreenSize();

        if (new_size.x != src_size.x or new_size.y != src_size.y) {
            texture.deinit();
            texture = try resizeWindow(window, renderer, new_size);
            src_size = new_size;
        }

        try texture.update(null, device.getPixels().ptr, src_size.x * 4);
        try renderer.renderTexture(texture, null, null);
        try renderer.present();

        const fps = fps_counter.update();

        var buf: [64]u8 = undefined;
        const title = try std.fmt.bufPrintZ(&buf, "{s} (FPS: {d:.2})", .{ app_name, fps });
        try window.setTitle(title);
    }
}

fn panicHandler(msg: []const u8, first_trace_addr: ?usize) noreturn {
    logger.deinit();
    std.debug.defaultPanic(msg, first_trace_addr);
}

fn resizeWindow(
    window: sdl3.video.Window,
    renderer: sdl3.render.Renderer,
    src_size: utopia.ScreenSize,
) !sdl3.render.Texture {
    const display = try window.getDisplayForWindow();
    const dst_size = try getBestSize(src_size, display);

    try window.setSize(dst_size.x, dst_size.y);
    try window.setPosition(.{ .centered = display }, .{ .centered = display });

    return try renderer.createTexture(
        .packed_xbgr_8_8_8_8,
        .streaming,
        src_size.x,
        src_size.y,
    );
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
