const fw = @import("framework");

const Self = @This();

mode: u32 = 0x0000_000e,
config: u32 = 0x0000_0040,
select: u32 = 0x0000_0014,
refresh: u32 = 0x0006_3634,

pub fn init() Self {
    return .{};
}

pub fn read(self: *Self, address: u32) u32 {
    return switch (@as(u3, @truncate(address >> 2))) {
        0 => self.mode,
        1 => self.config,
        3 => self.select,
        4 => self.refresh,
        else => fw.log.panic("Unmapped RI register read: {X:08}", .{address}),
    };
}

pub fn write(self: *Self, address: u32, value: u32, mask: u32) void {
    _ = self;
    _ = mask;

    switch (@as(u3, @truncate(address >> 2))) {
        else => fw.log.panic("Unmapped RI register write: {X:08} <= {X:08}", .{ address, value }),
    }
}
