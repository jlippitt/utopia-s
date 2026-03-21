const Self = @This();

counter: u7 = 0,
period: u7 = 0,
ctrl: Control = .{},
reload_flag: bool = false,

pub fn init() Self {
    return .{};
}

pub fn muted(self: *const Self) bool {
    return self.counter == 0;
}

pub fn setControl(self: *Self, value: u8) void {
    self.ctrl = @bitCast(value);
}

pub fn reset(self: *Self) void {
    self.reload_flag = true;
}

pub fn step(self: *Self) void {
    if (self.reload_flag) {
        self.counter = self.ctrl.period;

        if (!self.ctrl.halt) {
            self.reload_flag = false;
        }
    } else if (self.counter > 0) {
        self.counter -= 1;
    }
}

const Control = packed struct(u8) {
    period: u7 = 0,
    halt: bool = false,
};
