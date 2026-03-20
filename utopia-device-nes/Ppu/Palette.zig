const fw = @import("framework");

const Self = @This();

data: [32]u8 = @splat(0),

pub fn init() Self {
    return .{};
}

pub fn write(self: *Self, address: u15, value: u8) void {
    const mask: u5 = if ((address & 0x03) != 0) 0x1f else 0x0f;
    const index = @as(u5, @truncate(address)) & mask;
    self.data[index] = value & 0x3f;
    fw.log.trace("Palette Write: {X:02} <= {X:02}", .{ index, self.data[index] });
}
