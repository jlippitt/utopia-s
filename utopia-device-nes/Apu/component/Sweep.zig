pub const ComplementMode = enum(u1) {
    twos = 0,
    ones = 1,
};

const Self = @This();

enabled: bool = false,
divider: u3 = 0,
ctrl: Control = .{},
complement_mode: ComplementMode,
target_period: u16 = 0,
reload_flag: bool = false,
mute_flag: bool = false,

pub fn init(complement_mode: ComplementMode) Self {
    return .{
        .complement_mode = complement_mode,
    };
}

pub fn muted(self: *const Self) bool {
    return self.mute_flag;
}

pub fn setControl(self: *Self, value: u8) void {
    self.ctrl = @bitCast(value);
    self.reload_flag = true;
}

pub fn updateTargetPeriod(self: *Self, current_period: u16) void {
    const delta = current_period >> self.ctrl.shift;

    if (self.ctrl.negate) {
        self.target_period = current_period -| (delta + @intFromEnum(self.complement_mode));
    } else {
        self.target_period = current_period + delta;
    }

    self.mute_flag = current_period < 8 or self.target_period > 0x07ff;
}

pub fn step(self: *Self) ?u16 {
    var result: ?u16 = null;

    if (self.divider == 0 and self.ctrl.enable and !self.mute_flag) {
        result = self.target_period;
        self.updateTargetPeriod(self.target_period);
    }

    if (self.divider == 0 or self.reload_flag) {
        self.reload_flag = false;
        self.divider = self.ctrl.period;
    } else {
        self.divider -= 1;
    }

    return result;
}

const Control = packed struct(u8) {
    shift: u3 = 0,
    negate: bool = false,
    period: u3 = 0,
    enable: bool = false,
};
