const fw = @import("framework");
const Frame = @import("./FrameCounter.zig").Frame;
const Envelope = @import("./component/Envelope.zig");
const LengthCounter = @import("./component/LengthCounter.zig");
const Timer = @import("./component/Timer.zig");

const periods: [16]u16 = .{
    4,   8,   16,  32,  64,  96,   128,  160,
    202, 254, 380, 508, 762, 1016, 2034, 4068,
};

const Self = @This();

timer: Timer,
length_counter: LengthCounter,
envelope: Envelope,
lfsr: u15 = 1,
xor_bit: u4 = 1,

pub fn init() Self {
    return .{
        .timer = .init(periods[0], 1),
        .length_counter = .init(),
        .envelope = .init(),
    };
}

pub fn enabled(self: *const Self) bool {
    return !self.length_counter.muted();
}

pub fn sample(self: *const Self) u4 {
    if (self.length_counter.muted() or fw.num.bit(self.lfsr, 0)) {
        return 0;
    }

    return self.envelope.volume();
}

pub fn setControl(self: *Self, value: u8) void {
    self.length_counter.setHalted(fw.num.bit(value, 5));
    self.envelope.setControl(value);
}

pub fn setTimerLow(self: *Self, value: u8) void {
    self.timer.setPeriod(periods[@as(u4, @truncate(value))]);
    self.xor_bit = if (fw.num.bit(value, 7)) 6 else 1;
}

pub fn setTimerHigh(self: *Self, value: u8) void {
    self.length_counter.setPeriod(@truncate(value >> 3));
    self.envelope.reset();
}

pub fn setEnabled(self: *Self, value: bool) void {
    self.length_counter.setEnabled(value);
}

pub fn stepFrame(self: *Self, frame: Frame) void {
    self.envelope.step();

    if (frame == .half) {
        self.length_counter.step();
    }
}

pub fn stepCycle(self: *Self) void {
    if (self.timer.step()) {
        const feedback = (self.lfsr ^ (self.lfsr >> self.xor_bit)) & 1;
        self.lfsr = (self.lfsr >> 1) | (feedback << 14);
    }
}
