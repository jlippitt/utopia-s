const std = @import("std");
const fw = @import("framework");
const Pulse = @import("./Apu/Pulse.zig");

const sample_rate = fw.default_sample_rate;

// Allow for 2 frames worth of data
const sample_buffer_size = sample_rate * 2;

const clock_rate = 1048576;
const clock_multiplier = 1_000_000;
const sample_period = (clock_rate * clock_multiplier) / sample_rate;

const Self = @This();

sample_cycles: i32 = sample_period,
samples: std.ArrayList(fw.Sample),
pulse1: Pulse,
pulse2: Pulse,

pub fn init(arena: *std.heap.ArenaAllocator) error{OutOfMemory}!Self {
    const samples = try std.ArrayList(fw.Sample).initCapacity(
        arena.allocator(),
        sample_buffer_size,
    );

    return .{
        .samples = samples,
        .pulse1 = .init(),
        .pulse2 = .init(),
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

pub fn write(self: *Self, address: u8, value: u8) void {
    switch (address) {
        0x10 => self.pulse1.setSweep(value),
        0x11 => self.pulse1.setControl(value),
        0x12 => self.pulse1.setEnvelope(value),
        0x13 => self.pulse1.setTimerLow(value),
        0x14 => self.pulse1.setTimerHigh(value),
        0x15 => {}, // Pulse 2 has no sweep unit
        0x16 => self.pulse2.setControl(value),
        0x17 => self.pulse2.setEnvelope(value),
        0x18 => self.pulse2.setTimerLow(value),
        0x19 => self.pulse2.setTimerHigh(value),
        else => {}, // TODO
    }
}

pub fn stepFrame(self: *Self) void {
    self.pulse1.stepFrame();
    self.pulse2.stepFrame();
}

pub fn stepCycle(self: *Self) void {
    self.pulse1.stepCycle();
    self.pulse2.stepCycle();

    self.sample_cycles -= clock_multiplier;

    if (self.sample_cycles < 0) {
        self.sample_cycles += sample_period;

        const pulse1: u32 = self.pulse1.sample();
        const pulse2: u32 = self.pulse2.sample();

        const left = pulse1 + pulse2;
        const right = pulse1 + pulse2;

        self.samples.appendAssumeCapacity(.{
            @as(f32, @floatFromInt(left)) / 60.0,
            @as(f32, @floatFromInt(right)) / 60.0,
        });
    }
}
