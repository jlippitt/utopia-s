const std = @import("std");
const fw = @import("framework");
const Device = @import("./Device.zig");
const FrameCounter = @import("./Apu/FrameCounter.zig");
const Pulse = @import("./Apu/Pulse.zig");
const Triangle = @import("./Apu/Triangle.zig");

const Self = @This();

const sample_rate = fw.default_sample_rate;

// Allow for 2 frames worth of data
const sample_buffer_size = sample_rate * 2;

const clock_rate = 1789773;
const clock_multiplier = 1_000_000;
const sample_period = (clock_rate * clock_multiplier) / sample_rate;

sample_cycles: i32 = sample_period,
samples: std.ArrayList(fw.Sample),
frame_counter: FrameCounter,
pulse1: Pulse,
pulse2: Pulse,
triangle: Triangle,

pub fn init(arena: *std.heap.ArenaAllocator) error{OutOfMemory}!Self {
    const samples = try std.ArrayList(fw.Sample).initCapacity(
        arena.allocator(),
        sample_buffer_size,
    );

    return .{
        .samples = samples,
        .frame_counter = .init(),
        .pulse1 = .init(.ones),
        .pulse2 = .init(.twos),
        .triangle = .init(),
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

    fw.num.setBit(u8, &value, 0, self.pulse1.enabled());
    fw.num.setBit(u8, &value, 1, self.pulse2.enabled());
    fw.num.setBit(u8, &value, 2, self.triangle.enabled());
    fw.num.setBit(u8, &value, 6, self.getDevice().irq.has(.frame_counter));

    self.getDevice().irq.clear(.frame_counter);

    return value;
}

pub fn write(self: *Self, address: u16, value: u8) void {
    switch (@as(u5, @truncate(address))) {
        0x00 => self.pulse1.setControl(value),
        0x01 => self.pulse1.setSweep(value),
        0x02 => self.pulse1.setTimerLow(value),
        0x03 => self.pulse1.setTimerHigh(value),
        0x04 => self.pulse2.setControl(value),
        0x05 => self.pulse2.setSweep(value),
        0x06 => self.pulse2.setTimerLow(value),
        0x07 => self.pulse2.setTimerHigh(value),
        0x08 => self.triangle.setControl(value),
        0x0a => self.triangle.setTimerLow(value),
        0x0b => self.triangle.setTimerHigh(value),
        0x15 => {
            self.pulse1.setEnabled(fw.num.bit(value, 0));
            self.pulse2.setEnabled(fw.num.bit(value, 1));
            self.triangle.setEnabled(fw.num.bit(value, 2));
        },
        0x17 => self.frame_counter.setControl(value),
        else => {},
    }
}

pub fn step(self: *Self) void {
    const frame = self.frame_counter.step();

    if (frame) |some_frame| {
        self.pulse1.stepFrame(some_frame);
        self.pulse2.stepFrame(some_frame);
        self.triangle.stepFrame(some_frame);
    }

    self.pulse1.stepCycle();
    self.pulse2.stepCycle();
    self.triangle.stepCycle();

    self.sample_cycles -= clock_multiplier;

    if (self.sample_cycles < 0) {
        self.sample_cycles += sample_period;

        const pulse1: u5 = self.pulse1.sample();
        const pulse2: u5 = self.pulse2.sample();
        const triangle: u8 = self.triangle.sample();

        const pulse = pulse_table[pulse1 + pulse2];
        const tnd = tnd_table[triangle * 3];
        const sample = pulse + tnd;

        self.samples.appendAssumeCapacity(.{ sample, sample });
    }
}

pub fn getDevice(self: *Self) *Device {
    return @alignCast(@fieldParentPtr("apu", self));
}

const pulse_table: [31]f32 = blk: {
    var table: [31]f32 = undefined;

    for (&table, 0..) |*entry, index| {
        entry.* = 95.52 / (8128.0 / @as(f32, index) + 100.0);
    }

    break :blk table;
};

const tnd_table: [203]f32 = blk: {
    var table: [203]f32 = undefined;

    for (&table, 0..) |*entry, index| {
        entry.* = 163.67 / (24329.0 / @as(f32, index) + 100.0);
    }

    break :blk table;
};
