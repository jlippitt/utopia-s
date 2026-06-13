const std = @import("std");
const fw = @import("framework");

const sample_rate = fw.default_sample_rate;

// Allow for 2 frames worth of data
const sample_buffer_size = sample_rate * 2;

const clock_rate = 4194304;
const clock_multiplier = 1_000_000;
const sample_period = (clock_rate * clock_multiplier) / sample_rate;

const Self = @This();

sample_cycles: i32 = sample_period,
samples: std.ArrayList(fw.Sample),

pub fn init(arena: *std.heap.ArenaAllocator) error{OutOfMemory}!Self {
    const samples = try std.ArrayList(fw.Sample).initCapacity(
        arena.allocator(),
        sample_buffer_size,
    );

    return .{
        .samples = samples,
    };
}

pub fn getAudioState(self: *const Self) fw.AudioState {
    return .{
        .sample_rate = sample_rate,
        .sample_data = self.samples.items,
    };
}

pub fn clearSampleBuffer(self: *Self) void {
    self.samples.clearRetainingCapacity();
}

pub fn step(self: *Self, cycles: u64) void {
    self.sample_cycles -= @as(i32, @intCast(cycles)) * clock_multiplier;

    if (self.sample_cycles < 0) {
        self.sample_cycles += sample_period;

        const sample = 0;

        self.samples.appendAssumeCapacity(.{ sample, sample });
    }
}
