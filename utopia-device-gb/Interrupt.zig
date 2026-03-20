const fw = @import("framework");
const Device = @import("./Device.zig");

const Type = enum(u5) {
    vblank = 0x01,
    lcd_stat = 0x02,
    timer = 0x04,
    serial = 0x08,
    joypad = 0x10,
};

const Self = @This();

flags: u5 = 0,
enable: u5 = 0,

pub fn init() Self {
    return .{};
}

pub fn getFlags(self: *const Self) u8 {
    return @as(u8, 0xe0) | self.flags;
}

pub fn setFlags(self: *Self, value: u8) void {
    self.flags = @truncate(value);
    fw.log.debug("Interrupt Flags: {b:05}", .{self.flags});
    self.update();
}

pub fn getEnable(self: *const Self) u8 {
    return @as(u8, 0xe0) | self.enable;
}

pub fn setEnable(self: *Self, value: u8) void {
    self.enable = @truncate(value);
    fw.log.debug("Interrupt Enable: {b:05}", .{self.enable});
    self.update();
}

pub fn raise(self: *Self, int_type: Type) void {
    self.flags |= @intFromEnum(int_type);
    fw.log.debug("Interrupt Raised: {t}", .{int_type});
    self.update();
}

pub fn clear(self: *Self, int_type: Type) void {
    self.flags &= ~@intFromEnum(int_type);
    fw.log.debug("Interrupt Cleared: {t}", .{int_type});
    self.update();
}

fn update(self: *Self) void {
    self.getDevice().cpu.setInterrupt(self.flags & self.enable);
}

fn getDevice(self: *Self) *Device {
    return @alignCast(@fieldParentPtr("interrupt", self));
}
