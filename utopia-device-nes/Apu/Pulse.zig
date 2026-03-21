const fw = @import("framework");
const Frame = @import("./FrameCounter.zig").Frame;
const Envelope = @import("./component/Envelope.zig");
const LengthCounter = @import("./component/LengthCounter.zig");
const Sequencer = @import("./component/sequencer.zig").Sequencer;
const Sweep = @import("./component/Sweep.zig");
const Timer = @import("./component/Timer.zig");

pub const ComplementMode = Sweep.ComplementMode;

const duty_cycle: [4][8]u1 = .{
    .{ 0, 1, 0, 0, 0, 0, 0, 0 },
    .{ 0, 1, 1, 0, 0, 0, 0, 0 },
    .{ 0, 1, 1, 1, 1, 0, 0, 0 },
    .{ 1, 0, 0, 1, 1, 1, 1, 1 },
};

const Self = @This();

timer: Timer,
sequencer: Sequencer(u1, 8),
length_counter: LengthCounter,
envelope: Envelope,
sweep: Sweep,

pub fn init(complement_mode: ComplementMode) Self {
    return .{
        .timer = .init(0, 1),
        .sequencer = .init(&duty_cycle[0]),
        .length_counter = .init(),
        .envelope = .init(),
        .sweep = .init(complement_mode),
    };
}

pub fn enabled(self: *const Self) bool {
    return !self.length_counter.muted();
}

pub fn sample(self: *const Self) u4 {
    if (self.length_counter.muted() or self.sweep.muted()) {
        return 0;
    }

    return @as(u4, self.sequencer.sample()) * self.envelope.volume();
}

pub fn setControl(self: *Self, value: u8) void {
    self.sequencer.setSequence(&duty_cycle[value >> 6]);
    self.length_counter.setHalted(fw.num.bit(value, 5));
    self.envelope.setControl(value);
}

pub fn setSweep(self: *Self, value: u8) void {
    self.sweep.setControl(value);
}

pub fn setTimerLow(self: *Self, value: u8) void {
    self.timer.setPeriodLow(value);
    self.sweep.updateTargetPeriod(self.timer.getPeriod());
}

pub fn setTimerHigh(self: *Self, value: u8) void {
    self.timer.setPeriodHigh(value & 0x07);
    self.sweep.updateTargetPeriod(self.timer.getPeriod());
    self.length_counter.setPeriod(@truncate(value >> 3));
    self.sequencer.reset();
    self.envelope.reset();
}

pub fn setEnabled(self: *Self, value: bool) void {
    self.length_counter.setEnabled(value);
}

pub fn stepFrame(self: *Self, frame: Frame) void {
    self.envelope.step();

    if (frame == .half) {
        self.length_counter.step();

        if (self.sweep.step()) |period| {
            self.timer.setPeriod(period);
        }
    }
}

pub fn stepCycle(self: *Self) void {
    if (self.timer.step()) {
        self.sequencer.step();
    }
}
