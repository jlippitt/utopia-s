const Self = @This();

const period_table: [32]u8 = .{
    10,  254, 20, 2,  40, 4,  80, 6,
    160, 8,   60, 10, 14, 12, 26, 14,
    12,  16,  24, 18, 48, 20, 96, 22,
    192, 24,  72, 26, 16, 28, 32, 30,
};

enabled: bool = false,
halted: bool = false,
counter: u8 = 0,

pub fn init() Self {
    return .{};
}

pub fn muted(self: *const Self) bool {
    return self.counter == 0;
}

pub fn setHalted(self: *Self, halted: bool) void {
    self.halted = halted;
}

pub fn setEnabled(self: *Self, enabled: bool) void {
    self.enabled = enabled;

    if (!self.enabled) {
        self.counter = 0;
    }
}

pub fn setPeriod(self: *Self, index: u5) void {
    if (self.enabled) {
        self.counter = period_table[index];
    }
}

pub fn step(self: *Self) void {
    if (self.counter > 0 and !self.halted) {
        self.counter -= 1;
    }
}
