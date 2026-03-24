const fw = @import("framework");
const Device = @import("./Device.zig");

const period_masks: [4]u16 = .{ 1023, 15, 63, 255 };

const Self = @This();

divider: u16 = 0,
counter: u8 = 0,
modulo: u8 = 0,
ctrl: Control = .{},
period_mask: u16 = period_masks[0],

pub fn init() Self {
    return .{};
}

pub fn read(self: *const Self, address: u8) u8 {
    return switch (@as(u2, @truncate(address))) {
        0 => @truncate(self.divider >> 8),
        1 => self.counter,
        2 => self.modulo,
        3 => @bitCast(self.ctrl),
    };
}

pub fn write(self: *Self, address: u8, value: u8) void {
    switch (@as(u2, @truncate(address))) {
        0 => {
            self.divider = 0;
            fw.log.trace("Timer Divider Reset", .{});
        },
        1 => {
            self.counter = value;
            fw.log.trace("Timer Counter: {d}", .{self.counter});
        },
        2 => {
            self.modulo = value;
            fw.log.trace("Timer Modulo: {d}", .{self.modulo});
        },
        3 => {
            self.ctrl = @bitCast(value);
            self.period_mask = period_masks[self.ctrl.period];
            fw.log.trace("Timer Control: {any}", .{self.ctrl});
            fw.log.trace("Timer Period Mask: {d}", .{self.period_mask});
        },
    }
}

pub fn step(self: *Self, cycles: u16) void {
    self.divider +%= cycles;

    if (self.ctrl.enabled and (self.divider & self.period_mask) < cycles) {
        self.counter +%= 1;

        if (self.counter == 0) {
            self.counter = self.modulo;
            self.getDevice().interrupt.raise(.timer);
        }

        fw.log.trace("Timer Counter: {d}", .{self.counter});
    }
}

fn getDevice(self: *Self) *Device {
    return @alignCast(@fieldParentPtr("timer", self));
}

const Control = packed struct(u8) {
    period: u2 = 0,
    enabled: bool = false,
    __: u5 = 0,
};
