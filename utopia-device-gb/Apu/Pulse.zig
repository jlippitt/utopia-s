const Sequencer = @import("./component/sequencer.zig").Sequencer;
const Timer = @import("./component/Timer.zig");

const duty_cycle: [4][8]u1 = .{
    .{ 1, 1, 1, 1, 1, 1, 1, 0 },
    .{ 0, 1, 1, 1, 1, 1, 1, 0 },
    .{ 0, 1, 1, 1, 1, 0, 0, 0 },
    .{ 1, 0, 0, 0, 0, 0, 0, 1 },
};

const Self = @This();

timer: Timer,
sequencer: Sequencer(u1, 8),

pub fn init() Self {
    return .{
        .timer = .init(),
        .sequencer = .init(&duty_cycle[0]),
    };
}

pub fn sample(self: *Self) u4 {
    return @as(u4, self.sequencer.sample()) * 15;
}

pub fn setSweep(self: *Self, value: u8) void {
    _ = self;
    _ = value;
}

pub fn setControl(self: *Self, value: u8) void {
    // TODO: Length counter
    self.sequencer.setSequence(&duty_cycle[value >> 6]);
}

pub fn setEnvelope(self: *Self, value: u8) void {
    _ = self;
    _ = value;
}

pub fn setTimerLow(self: *Self, value: u8) void {
    self.timer.setFrequencyLow(value);
}

pub fn setTimerHigh(self: *Self, value: u8) void {
    self.timer.setFrequencyHigh(value & 0x07);

    if ((value & 0x80) != 0) {
        self.timer.reset();
        // TODO: Other components
    }
}

pub fn stepCycle(self: *Self) void {
    if (self.timer.step()) {
        self.sequencer.step();
    }
}
