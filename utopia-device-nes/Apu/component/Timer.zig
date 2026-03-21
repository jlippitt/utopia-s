const Self = @This();

counter: u16,
period: u16,
shift: u1,

pub fn init(period: u16, shift: u1) Self {
    return .{
        .counter = (@as(u16, 1) << shift) - 1,
        .period = period,
        .shift = shift,
    };
}

pub fn getPeriod(self: *const Self) u16 {
    return self.period;
}

pub fn setPeriod(self: *Self, value: u16) void {
    self.period = value;
}

pub fn setPeriodLow(self: *Self, value: u8) void {
    self.period = (self.period & 0xff00) | value;
}

pub fn setPeriodHigh(self: *Self, value: u8) void {
    self.period = (self.period & 0xff) | @as(u16, value) << 8;
}

pub fn step(self: *Self) bool {
    if (self.counter != 0) {
        @branchHint(.likely);
        self.counter -= 1;
        return false;
    }

    self.counter = ((self.period + 1) << self.shift) - 1;
    return true;
}
