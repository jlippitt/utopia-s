const fw = @import("framework");
const Frame = @import("./FrameCounter.zig").Frame;
const LengthCounter = @import("./component/LengthCounter.zig");
const Sequencer = @import("./component/sequencer.zig").Sequencer;
const Timer = @import("./component/Timer.zig");

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

pub fn init() Self {
    return .{
        .timer = .init(0, 1),
        .sequencer = .init(&duty_cycle[0]),
        .length_counter = .init(),
    };
}

pub fn isEnabled(self: *const Self) bool {
    return !self.length_counter.muted();
}

pub fn sample(self: *const Self) u4 {
    // TODO: Sweep
    if (self.length_counter.muted()) {
        return 0;
    }

    // TODO: Envelope
    return @as(u4, self.sequencer.sample()) * 15;
}

pub fn setControl(self: *Self, value: u8) void {
    self.sequencer.setSequence(&duty_cycle[value >> 6]);
    self.length_counter.setHalted(fw.num.bit(value, 5));
    // TODO: Envelope
}

pub fn setSweep(self: *Self, value: u8) void {
    // TODO: Sweep
    _ = self;
    _ = value;
}

pub fn setTimerLow(self: *Self, value: u8) void {
    self.timer.setPeriodLow(value);
}

pub fn setTimerHigh(self: *Self, value: u8) void {
    self.timer.setPeriodHigh(value & 0x07);
    self.length_counter.setPeriod(@truncate(value >> 3));
    self.sequencer.reset();
    // TODO: Envelope
    // TODO: Sweep
}

pub fn setEnabled(self: *Self, enabled: bool) void {
    self.length_counter.setEnabled(enabled);
}

pub fn stepFrame(self: *Self, frame: Frame) void {
    // TODO: Envelope

    if (frame == .half) {
        self.length_counter.step();
        // TODO: Sweep
    }
}

pub fn stepCycle(self: *Self) void {
    if (self.timer.step()) {
        self.sequencer.step();
    }
}
