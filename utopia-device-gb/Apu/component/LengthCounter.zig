const Self = @This();

counter: u8 = 0,
frequency: u8 = 0,
max_frequency: u8 = 0,
enabled: bool = false,

pub fn init(max_frequency: u8) Self {
    return .{
        .max_frequency = max_frequency,
    };
}

pub fn reset(self: *Self) void {
    if (self.counter == self.max_frequency) {
        self.counter = 0;
    }
}

pub fn setEnabled(self: *Self, enabled: bool) void {
    self.enabled = enabled;

    if (self.enabled) {
        self.counter = self.frequency;
    }
}

pub fn setFrequency(self: *Self, value: u8) void {
    self.frequency = value;

    if (self.enabled) {
        self.counter = self.frequency;
    }
}

pub fn step(self: *Self) bool {
    if (!self.enabled) {
        return false;
    }

    if (self.counter != self.max_frequency) {
        @branchHint(.likely);
        self.counter += 1;
        return false;
    }

    return true;
}
