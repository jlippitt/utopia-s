const std = @import("std");
const sdl3 = @import("sdl3");
const utopia = @import("utopia");

const app_name = "Utopia-S";

const Self = @This();

window: sdl3.video.Window,
renderer: sdl3.render.Renderer,
texture: sdl3.render.Texture,
resolution: utopia.Resolution,

pub fn init(resolution: utopia.Resolution) error{SdlError}!Self {
    const init_size = try getBestSize(resolution, null);

    const window = try sdl3.video.Window.init(app_name, init_size.x, init_size.y, .{});
    errdefer window.deinit();

    const renderer = try sdl3.render.Renderer.init(window, null);
    errdefer renderer.deinit();

    var texture = try resizeWindow(window, renderer, resolution);
    errdefer texture.deinit();

    return .{
        .window = window,
        .renderer = renderer,
        .texture = texture,
        .resolution = resolution,
    };
}

pub fn deinit(self: *Self) void {
    self.texture.deinit();
    self.renderer.deinit();
    self.window.deinit();
}

pub fn onWindowDisplayChanged(self: *Self) error{SdlError}!void {
    self.texture.deinit();
    self.texture = try resizeWindow(self.window, self.renderer, self.resolution);
}

pub fn setResolution(self: *Self, resolution: utopia.Resolution) error{SdlError}!void {
    if (resolution.x == self.resolution.x and resolution.y == self.resolution.y) {
        return;
    }

    self.texture.deinit();
    self.texture = try resizeWindow(self.window, self.renderer, resolution);
    self.resolution = resolution;
}

pub fn setFps(self: *Self, fps: f64) error{ NoSpaceLeft, SdlError }!void {
    var buf: [64]u8 = undefined;
    const title = try std.fmt.bufPrintZ(&buf, "{s} (FPS: {d:.2})", .{ app_name, fps });
    try self.window.setTitle(title);
}

pub fn update(self: *Self, pixel_data: []const u8) error{SdlError}!void {
    try self.texture.update(null, pixel_data.ptr, self.resolution.x * 4);
    try self.renderer.renderTexture(self.texture, null, null);
    try self.renderer.present();
}

fn resizeWindow(
    window: sdl3.video.Window,
    renderer: sdl3.render.Renderer,
    src_size: utopia.Resolution,
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
    min_size: utopia.Resolution,
    active_display: ?sdl3.video.Display,
) !utopia.Resolution {
    const display = active_display orelse (try sdl3.video.getDisplays())[0];
    const bounds = try display.getUsableBounds();

    const max_size: utopia.Resolution = .{
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
