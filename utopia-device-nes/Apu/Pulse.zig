const Sequencer = @import("./component/sequencer.zig").Sequencer;
const Timer = @import("./component/Timer.zig");
const Frame = @import("./FrameCounter.zig").Frame;

const duty_cycle: [4][8]u1 = .{
    .{ 0, 1, 0, 0, 0, 0, 0, 0 },
    .{ 0, 1, 1, 0, 0, 0, 0, 0 },
    .{ 0, 1, 1, 1, 1, 0, 0, 0 },
    .{ 1, 0, 0, 1, 1, 1, 1, 1 },
};

const Self = @This();

timer: Timer,
sequencer: Sequencer(u1, 8),

pub fn init() Self {
    return .{
        .timer = .init(0, 1),
        .sequencer = .init(&duty_cycle[0]),
    };
}

pub fn isEnabled(self: *const Self) bool {
    // TODO: Length counter
    _ = self;
    return true;
}

pub fn sample(self: *const Self) u4 {
    // TODO: Length counter
    // TODO: Envelope
    // TODO: Sweep
    return @as(u4, self.sequencer.sample()) * 15;
}

pub fn setControl(self: *Self, value: u8) void {
    self.sequencer.setSequence(&duty_cycle[value >> 6]);
    // TODO: Length counter
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
    self.sequencer.reset();
    // TODO: Length counter
    // TODO: Envelope
    // TODO: Sweep
}

pub fn setEnabled(self: *Self, enabled: bool) void {
    // TODO: Length counter
    _ = self;
    _ = enabled;
}

pub fn stepFrame(self: *Self, frame: Frame) void {
    // TODO: Length counter
    // TODO: Envelope
    // TODO: Sweep
    _ = self;
    _ = frame;
}

pub fn stepCycle(self: *Self) void {
    if (self.timer.step()) {
        self.sequencer.step();
    }
}
