const Sequencer = @import("./component/sequencer.zig").Sequencer;
const Timer = @import("./component/Timer.zig");
const LengthCounter = @import("./component/LengthCounter.zig");

const duty_cycle: [4][8]u1 = .{
    .{ 1, 1, 1, 1, 1, 1, 1, 0 },
    .{ 0, 1, 1, 1, 1, 1, 1, 0 },
    .{ 0, 1, 1, 1, 1, 0, 0, 0 },
    .{ 1, 0, 0, 0, 0, 0, 0, 1 },
};

const Self = @This();

timer: Timer,
sequencer: Sequencer(u1, 8),
length_counter: LengthCounter,
muted: bool = true,

pub fn init() Self {
    return .{
        .timer = .init(),
        .sequencer = .init(&duty_cycle[0]),
        .length_counter = .init(63),
    };
}

pub fn sample(self: *Self) u4 {
    if (self.muted) {
        return 0;
    }

    return @as(u4, self.sequencer.sample()) * 15;
}

pub fn setSweep(self: *Self, value: u8) void {
    _ = self;
    _ = value;
}

pub fn setControl(self: *Self, value: u8) void {
    self.length_counter.setFrequency(value & 0x3f);
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
    self.length_counter.setEnabled((value & 0x40) != 0);

    if ((value & 0x80) != 0) {
        self.timer.reset();
        self.length_counter.reset();
        // TODO: Other components
        self.muted = false;
    }
}

pub fn stepFrame(self: *Self) void {
    if (self.length_counter.step()) {
        self.muted = true;
    }
}

pub fn stepCycle(self: *Self) void {
    if (self.timer.step()) {
        self.sequencer.step();
    }
}
