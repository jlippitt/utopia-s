const fw = @import("framework");

const Self = @This();

status: Status = .{},

pub fn init() Self {
    return .{};
}

pub fn read(self: *Self, address: u32) u32 {
    return switch (@as(u4, @truncate(address >> 2))) {
        4 => @bitCast(self.status),
        else => fw.log.panic("Unmapped PI register read: {X:08}", .{address}),
    };
}

pub fn write(self: *Self, address: u32, value: u32, mask: u32) void {
    _ = self;
    _ = mask;

    switch (@as(u4, @truncate(address >> 2))) {
        4 => {}, // TODO: PI interrupts
        else => fw.log.panic("Unmapped PI register write: {X:08} <= {X:08}", .{ address, value }),
    }
}

const Status = packed struct(u32) {
    dma_busy: bool = false,
    io_busy: bool = false,
    dma_error: bool = false,
    interrupt: bool = false,
    __: u28 = 0,
};
