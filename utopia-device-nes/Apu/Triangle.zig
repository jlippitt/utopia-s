const fw = @import("framework");
const Frame = @import("./FrameCounter.zig").Frame;
const LengthCounter = @import("./component/LengthCounter.zig");
const LinearCounter = @import("./component/LinearCounter.zig");
const Sequencer = @import("./component/sequencer.zig").Sequencer;
const Timer = @import("./component/Timer.zig");

const triangle_wave: [32]u4 = .{
    15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5,  4,  3,  2,  1,  0,
    0,  1,  2,  3,  4,  5,  6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
};

const Self = @This();

timer: Timer,
sequencer: Sequencer(u4, 32),
length_counter: LengthCounter,
linear_counter: LinearCounter,

pub fn init() Self {
    return .{
        .timer = .init(0, 0),
        .sequencer = .init(&triangle_wave),
        .length_counter = .init(),
        .linear_counter = .init(),
    };
}

pub fn enabled(self: *const Self) bool {
    return !self.length_counter.muted();
}

pub fn sample(self: *const Self) u4 {
    return self.sequencer.sample();
}

pub fn setControl(self: *Self, value: u8) void {
    self.length_counter.setHalted(fw.num.bit(value, 7));
    self.linear_counter.setControl(value);
}

pub fn setTimerLow(self: *Self, value: u8) void {
    self.timer.setPeriodLow(value);
}

pub fn setTimerHigh(self: *Self, value: u8) void {
    self.timer.setPeriodHigh(value & 0x07);
    self.length_counter.setPeriod(@truncate(value >> 3));
    self.linear_counter.reset();
}

pub fn setEnabled(self: *Self, value: bool) void {
    self.length_counter.setEnabled(value);
}

pub fn stepFrame(self: *Self, frame: Frame) void {
    self.linear_counter.step();

    if (frame == .half) {
        self.length_counter.step();
    }
}

pub fn stepCycle(self: *Self) void {
    if (self.timer.step() and
        self.timer.getPeriod() >= 2 and
        !self.length_counter.muted() and
        !self.linear_counter.muted())
    {
        self.sequencer.step();
    }
}
