const std = @import("std");

const window_size = 32;
const initial_fps = 60.0;
const clock: std.Io.Clock = .awake;

const Self = @This();

time: std.Io.Timestamp,
total: f64 = initial_fps * window_size,
index: u5 = 0,
window: [window_size]f64 = @splat(initial_fps),

pub fn init(io: std.Io) !Self {
    return .{
        .time = .now(io, clock),
    };
}

pub fn update(self: *Self, io: std.Io) f64 {
    const now = std.Io.Timestamp.now(io, clock);
    const delta = self.time.durationTo(now).toNanoseconds();
    self.time = now;

    const fps = std.time.ns_per_s / @as(f64, @floatFromInt(delta));

    self.total -= self.window[self.index];
    self.total += fps;
    self.window[self.index] = fps;
    self.index +%= 1;

    return self.total / window_size;
}
