const max_frequency = 2047;

const Self = @This();

counter: u16,
frequency: u16,

pub fn init() Self {
    return .{
        .frequency = 0,
        .counter = 0,
    };
}

pub fn setFrequencyLow(self: *Self, value: u8) void {
    self.frequency = (self.frequency & 0xff00) | value;
}

pub fn setFrequencyHigh(self: *Self, value: u8) void {
    self.frequency = (self.frequency & 0xff) | @as(u16, value) << 8;
}

pub fn reset(self: *Self) void {
    self.counter = self.frequency;
}

pub fn step(self: *Self) bool {
    if (self.counter == max_frequency) {
        @branchHint(.unlikely);
        self.counter = self.frequency;
        return true;
    }

    self.counter += 1;
    return false;
}
