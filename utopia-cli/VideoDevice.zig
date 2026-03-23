const std = @import("std");
const sdl3 = @import("sdl3");
const utopia = @import("utopia");

const app_name = "Utopia-S";

const Self = @This();

window: sdl3.video.Window,
renderer: sdl3.render.Renderer,
texture: sdl3.render.Texture,
resolution: utopia.Resolution,
dst_rect: sdl3.rect.FRect,
full_screen: bool,

pub fn init(resolution: utopia.Resolution, full_screen: bool) error{SdlError}!Self {
    const init_size = try getBestSize(resolution, null, full_screen);

    const window = try sdl3.video.Window.init(app_name, init_size.w, init_size.h, .{
        .fullscreen = full_screen,
    });
    errdefer window.deinit();

    const renderer = try sdl3.render.Renderer.init(window, null);
    errdefer renderer.deinit();

    const texture = try createTexture(renderer, resolution);
    errdefer texture.deinit();

    const dst_rect = try resizeWindow(
        window,
        resolution,
        full_screen,
    );

    return .{
        .window = window,
        .renderer = renderer,
        .texture = texture,
        .resolution = resolution,
        .dst_rect = dst_rect,
        .full_screen = full_screen,
    };
}

pub fn deinit(self: *Self) void {
    self.texture.deinit();
    self.renderer.deinit();
    self.window.deinit();
}

pub fn onWindowDisplayChanged(self: *Self) error{SdlError}!void {
    self.dst_rect = try resizeWindow(self.window, self.resolution, self.full_screen);
}

pub fn toggleFullScreen(self: *Self) error{SdlError}!void {
    self.full_screen = !self.full_screen;
    try self.window.setFullscreen(self.full_screen);
    self.dst_rect = try resizeWindow(self.window, self.resolution, self.full_screen);
}

pub fn setResolution(self: *Self, resolution: utopia.Resolution) error{SdlError}!void {
    if (resolution.x == self.resolution.x and resolution.y == self.resolution.y) {
        return;
    }

    self.dst_rect = try resizeWindow(self.window, resolution, self.full_screen);

    self.texture.deinit();
    self.texture = try createTexture(self.renderer, resolution);

    self.resolution = resolution;
}

pub fn setFps(self: *Self, fps: f64) error{ NoSpaceLeft, SdlError }!void {
    var buf: [64]u8 = undefined;
    const title = try std.fmt.bufPrintZ(&buf, "{s} (FPS: {d:.2})", .{ app_name, fps });
    try self.window.setTitle(title);
}

pub fn update(self: *Self, pixel_data: []const u8) error{SdlError}!void {
    try self.texture.update(null, pixel_data.ptr, self.resolution.x * 4);
    try self.renderer.renderTexture(self.texture, null, self.dst_rect);
    try self.renderer.present();
}

fn createTexture(
    renderer: sdl3.render.Renderer,
    size: utopia.Resolution,
) error{SdlError}!sdl3.render.Texture {
    return renderer.createTexture(
        .packed_xbgr_8_8_8_8,
        .streaming,
        size.x,
        size.y,
    );
}

fn resizeWindow(
    window: sdl3.video.Window,
    src_size: utopia.Resolution,
    full_screen: bool,
) error{SdlError}!sdl3.rect.FRect {
    const display = try window.getDisplayForWindow();
    const dst_rect = try getBestSize(src_size, display, full_screen);

    if (!full_screen) {
        try window.setSize(dst_rect.w, dst_rect.h);
        try window.setPosition(.{ .centered = display }, .{ .centered = display });
    }

    return dst_rect.asOtherRect(f32);
}

fn getBestSize(
    min_size: utopia.Resolution,
    active_display: ?sdl3.video.Display,
    full_screen: bool,
) !sdl3.rect.Rect(u32) {
    const display = active_display orelse (try sdl3.video.getDisplays())[0];

    const bounds = if (full_screen)
        try display.getBounds()
    else
        try display.getUsableBounds();

    const max_size: utopia.Resolution = .{
        .x = @intCast(bounds.w),
        .y = @intCast(bounds.h),
    };

    const x_scale = max_size.x / min_size.x;
    const y_scale = max_size.y / min_size.y;
    const scale = @min(x_scale, y_scale);

    const dst_size: utopia.Resolution = .{
        .x = min_size.x * scale,
        .y = min_size.y * scale,
    };

    const dst_rect: sdl3.rect.Rect(u32) = if (full_screen)
        .{
            .x = (max_size.x - dst_size.x) / 2,
            .y = (max_size.y - dst_size.y) / 2,
            .w = dst_size.x,
            .h = dst_size.y,
        }
    else
        .{
            .x = 0,
            .y = 0,
            .w = dst_size.x,
            .h = dst_size.y,
        };

    return dst_rect;
}
