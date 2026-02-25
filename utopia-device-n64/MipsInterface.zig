const fw = @import("framework");
const register = @import("./register.zig");

const Self = @This();

mode: Mode = .{},
mask: Mask = .{},

pub fn init() Self {
    return .{};
}

pub fn read(self: *Self, address: u32) u32 {
    return switch (@as(u2, @truncate(address >> 2))) {
        0 => @bitCast(self.mode),
        1 => 0x0202_0102,
        3 => @bitCast(self.mask),
        else => fw.log.panic("Unmapped MI register read: {X:08}", .{address}),
    };
}

pub fn write(self: *Self, address: u32, value: u32, mask: u32) void {
    switch (@as(u2, @truncate(address >> 2))) {
        0 => {
            // Only the lower 7 bits ('repeat_count') are written this way
            fw.num.writeMasked(u32, @ptrCast(&self.mode), @truncate(value), @truncate(mask & 7));

            const masked_value = value & mask;

            register.setFlag(&self.mode, "repeat", masked_value, 7);
            register.setFlag(&self.mode, "ebus", masked_value, 9);
            register.setFlag(&self.mode, "upper", masked_value, 12);

            if (self.mode.repeat) {
                fw.log.unimplemented("MI Repeat Mode", .{});
            }

            if (self.mode.ebus) {
                fw.log.unimplemented("MI EBus Mode", .{});
            }

            if (self.mode.upper) {
                fw.log.unimplemented("MI Upper Mode", .{});
            }

            // TODO: RDP interrupts

            fw.log.debug("MI_MODE: {any}", .{self.mask});
        },
        3 => {
            const masked_value = value & mask;

            register.setFlag(&self.mask, "sp", masked_value, 0);
            register.setFlag(&self.mask, "si", masked_value, 2);
            register.setFlag(&self.mask, "ai", masked_value, 4);
            register.setFlag(&self.mask, "vi", masked_value, 6);
            register.setFlag(&self.mask, "pi", masked_value, 8);
            register.setFlag(&self.mask, "dp", masked_value, 10);

            fw.log.debug("MI_MASK: {any}", .{self.mask});
        },
        else => fw.log.panic("Unmapped MI register write: {X:08} <= {X:08}", .{ address, value }),
    }
}

const Mode = packed struct(u32) {
    repeat_count: u7 = 0,
    repeat: bool = false,
    ebus: bool = false,
    upper: bool = false,
    __: u22 = 0,
};

const Mask = packed struct(u32) {
    sp: bool = false,
    si: bool = false,
    ai: bool = false,
    vi: bool = false,
    pi: bool = false,
    dp: bool = false,
    __: u26 = 0,
};
