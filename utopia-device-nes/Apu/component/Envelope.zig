const fw = @import("framework");

const Self = @This();

decay: u4 = 0,
divider: u4 = 0,
ctrl: Control = .{},
start_flag: bool = false,

pub fn init() Self {
    return .{};
}

pub fn volume(self: *const Self) u4 {
    if (self.ctrl.constant) {
        return self.ctrl.period;
    }

    return self.decay;
}

pub fn setControl(self: *Self, value: u8) void {
    self.ctrl = @bitCast(value);
}

pub fn reset(self: *Self) void {
    self.start_flag = true;
}

pub fn step(self: *Self) void {
    if (self.start_flag) {
        self.start_flag = false;
        self.decay = 15;
        self.divider = self.ctrl.period;
        return;
    }

    if (self.divider > 0) {
        self.divider -= 1;
        return;
    }

    self.divider = self.ctrl.period;

    if (self.decay > 0) {
        self.decay -= 1;
    } else if (self.ctrl.loop) {
        self.decay = 15;
    }
}

const Control = packed struct(u8) {
    period: u4 = 0,
    constant: bool = false,
    loop: bool = false,
    __: u2 = 0,
};
