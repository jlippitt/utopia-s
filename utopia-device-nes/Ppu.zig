const fw = @import("framework");

const Self = @This();

pub fn init() Self {
    return .{};
}

pub fn read(self: *Self, address: u16) u8 {
    _ = self;

    return switch (@as(u3, @truncate(address))) {
        2 => 0x80,
        else => fw.log.todo("PPU register read: {X:04}", .{address}),
    };
}

pub fn write(self: *Self, address: u16, value: u8) void {
    _ = self;

    switch (@as(u3, @truncate(address))) {
        else => fw.log.trace("TODO: PPU register write: {X:04} <= {X:02}", .{ address, value }),
    }
}
