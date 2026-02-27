const std = @import("std");

const window_size = 32;
const initial_fps = 60.0;

const Self = @This();

timer: std.time.Timer,
total: f64 = initial_fps * window_size,
index: u5 = 0,
window: [window_size]f64 = @splat(initial_fps),

pub fn init() !Self {
    return .{
        .timer = try .start(),
    };
}

pub fn update(self: *Self) f64 {
    const delta = self.timer.lap();
    const fps = std.time.ns_per_s / @as(f64, @floatFromInt(delta));

    self.total -= self.window[self.index];
    self.total += fps;
    self.window[self.index] = fps;
    self.index +%= 1;

    return self.total / window_size;
}
