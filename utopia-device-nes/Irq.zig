const fw = @import("framework");
const Device = @import("./Device.zig");

const Type = enum(u3) {
    frame_counter = 0x01,
    dmc = 0x02,
    mapper = 0x04,
};

const Self = @This();

status: u3 = 0,

pub fn init() Self {
    return .{};
}

pub fn has(self: *const Self, irq_type: Type) bool {
    return (self.status & @intFromEnum(irq_type)) != 0;
}

pub fn raise(self: *Self, irq_type: Type) void {
    self.status |= @intFromEnum(irq_type);
    fw.log.debug("IRQ Raised: {t}", .{irq_type});
    self.update();
}

pub fn clear(self: *Self, irq_type: Type) void {
    self.status &= ~@intFromEnum(irq_type);
    fw.log.debug("IRQ Cleared: {t}", .{irq_type});
    self.update();
}

fn update(self: *Self) void {
    self.getDevice().cpu.setIrq(self.status != 0);
}

fn getDevice(self: *Self) *Device {
    return @alignCast(@fieldParentPtr("irq", self));
}
