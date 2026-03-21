const std = @import("std");
const fw = @import("framework");
const Device = @import("./Device.zig");
const FrameCounter = @import("./Apu/FrameCounter.zig");

const Self = @This();

const sample_rate = fw.default_sample_rate;

// Allow for 2 frames worth of data
const sample_buffer_size = sample_rate * 2;

const clock_rate = 1789773;
const clock_multiplier = 1_000_000;
const sample_period = (clock_rate * clock_multiplier) / sample_rate;

frame_counter: FrameCounter,
sample_cycles: i32 = sample_period,
samples: std.ArrayList(fw.Sample),

pub fn init(arena: *std.heap.ArenaAllocator) error{OutOfMemory}!Self {
    const samples = try std.ArrayList(fw.Sample).initCapacity(
        arena.allocator(),
        sample_buffer_size,
    );

    return .{
        .frame_counter = .init(),
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

pub fn read(self: *Self, prev_value: u8) u8 {
    var value = prev_value & 0x20;

    value |= if (self.getDevice().irq.has(.frame_counter)) 0x40 else 0;

    self.getDevice().irq.clear(.frame_counter);

    return value;
}

pub fn write(self: *Self, address: u16, value: u8) void {
    switch (@as(u5, @truncate(address))) {
        0x17 => self.frame_counter.setControl(value),
        else => {},
    }
}

pub fn step(self: *Self) void {
    const event = self.frame_counter.step();

    if (event) |some_event| {
        // TODO: Step audio channels
        _ = some_event;
    }

    self.sample_cycles -= clock_multiplier;

    if (self.sample_cycles < 0) {
        self.sample_cycles += sample_period;
        self.samples.appendAssumeCapacity(.{ 0, 0 });
    }
}

pub fn getDevice(self: *Self) *Device {
    return @alignCast(@fieldParentPtr("apu", self));
}
