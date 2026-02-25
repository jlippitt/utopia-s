const fw = @import("framework");

const Self = @This();

status: Status = .{},

pub fn init() Self {
    return .{};
}

pub fn readCommand(self: *Self, address: u32) u32 {
    return self.readRegister(@truncate(address >> 2));
}

pub fn writeCommand(self: *Self, address: u32, value: u32, mask: u32) void {
    self.writeRegister(@truncate(address >> 2), value, mask);
}

pub fn readRegister(self: *Self, index: u3) u32 {
    return switch (index) {
        3 => @bitCast(self.status),
        else => fw.log.panic("Unmapped RDP register read: {}", .{index}),
    };
}

pub fn writeRegister(self: *Self, index: u3, value: u32, mask: u32) void {
    _ = self;
    _ = mask;

    switch (index) {
        else => fw.log.panic("Unmapped RDP register write: {} <= {X:08}", .{ index, value }),
    }
}

const Status = packed struct(u32) {
    xbus: bool = false,
    freeze: bool = false,
    flush: bool = false,
    gclk: bool = false,
    tmem_busy: bool = false,
    pipe_busy: bool = false,
    cmd_busy: bool = false,
    cbuf_ready: bool = false,
    dma_busy: bool = false,
    end_pending: bool = false,
    start_pending: bool = false,
    __: u21 = 0,
};
