const fw = @import("framework");

const Self = @This();

button_state: [2]ButtonState = @splat(.{}),
polled_state: [2]u8 = @splat(0),
strobe: bool = false,

pub fn init() Self {
    return .{};
}

pub fn update(self: *Self, new_state: *const fw.ControllerState) void {
    const button = &new_state.button;
    const state = &self.button_state[0];

    state.a = button.south or button.east;
    state.b = button.west or button.north;
    state.select = button.back;
    state.start = button.start;
    state.up = button.dpad_up;
    state.down = button.dpad_down;
    state.left = button.dpad_left;
    state.right = button.dpad_right;
}

pub fn read(self: *Self, address: u16, prev_value: u8) u8 {
    const player: u1 = @truncate(address);

    const result: u8 = if (self.strobe)
        @bitCast(self.button_state[player])
    else blk: {
        const state = &self.polled_state[player];
        const value = state.*;
        state.* = 0x80 | (state.* >> 1);
        break :blk value;
    };

    return (prev_value & 0xe0) | (result & 0x01);
}

pub fn write(self: *Self, value: u8) void {
    const strobe = fw.num.bit(value, 0);

    if (!strobe and self.strobe) {
        self.polled_state = @bitCast(self.button_state);
        fw.log.debug("Joypad state latched", .{});
    }

    self.strobe = strobe;
}

const ButtonState = packed struct(u8) {
    a: bool = false,
    b: bool = false,
    select: bool = false,
    start: bool = false,
    up: bool = false,
    down: bool = false,
    left: bool = false,
    right: bool = false,
};
