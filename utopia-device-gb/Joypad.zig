const fw = @import("framework");

const Self = @This();

dpad_state: DpadState = .{},
button_state: ButtonState = .{},
dpad_select: bool = false,
button_select: bool = false,

pub fn init() Self {
    return .{};
}

pub fn update(self: *Self, new_state: *const fw.ControllerState) void {
    const button = &new_state.button;

    self.button_state.a = button.south or button.east;
    self.button_state.b = button.west or button.north;
    self.button_state.select = button.back;
    self.button_state.start = button.start;

    self.dpad_state.right = button.dpad_right;
    self.dpad_state.left = button.dpad_left;
    self.dpad_state.up = button.dpad_up;
    self.dpad_state.down = button.dpad_down;
}

pub fn read(self: *const Self) u8 {
    var value: u8 = 0xff;

    if (self.dpad_select) {
        value &= ~@as(u8, @bitCast(self.dpad_state));
    }

    if (self.button_select) {
        value &= ~@as(u8, @bitCast(self.button_state));
    }

    return value;
}

pub fn write(self: *Self, value: u8) void {
    self.dpad_select = !fw.num.bit(value, 4);
    self.button_select = !fw.num.bit(value, 5);
}

const DpadState = packed struct(u8) {
    right: bool = false,
    left: bool = false,
    up: bool = false,
    down: bool = false,
    __: u4 = 0,
};

const ButtonState = packed struct(u8) {
    a: bool = false,
    b: bool = false,
    select: bool = false,
    start: bool = false,
    __: u4 = 0,
};
