const fw = @import("framework");

const Self = @This();

dram_addr: u24 = 0,
length: u18 = 0,
dma_enable: bool = false,
status: Status = .{},
dacrate: u14 = 0,
bitrate: u4 = 0,

pub fn init() Self {
    return .{};
}

pub fn read(self: *Self, address: u32) u32 {
    return switch (@as(u3, @truncate(address >> 2))) {
        0, 1, 2, 4, 5 => self.length,
        3 => blk: {
            self.status.enabled = self.dma_enable;
            break :blk @bitCast(self.status);
        },
        else => fw.log.panic("Unmapped AI register read: {X:08}", .{address}),
    };
}

pub fn write(self: *Self, address: u32, value: u32, mask: u32) void {
    switch (@as(u3, @truncate(address >> 2))) {
        0 => {
            fw.num.writeMasked(
                u24,
                &self.dram_addr,
                @truncate(value),
                @truncate(mask & ~@as(u32, 7)),
            );

            fw.log.debug("AI_DRAM_ADDR: {X:08}", .{self.dram_addr});
        },
        1 => {
            fw.num.writeMasked(
                u18,
                &self.length,
                @truncate(value),
                @truncate(mask & ~@as(u32, 7)),
            );

            fw.log.debug("AI_LENGTH: {X:08}", .{self.length});
        },
        2 => {
            fw.num.writeMasked(
                u1,
                @ptrCast(&self.dma_enable),
                @truncate(value),
                @truncate(mask),
            );

            fw.log.debug("AI_CONTROL (Dma Enable): {}", .{self.dma_enable});
        },
        3 => {}, // TODO: AI interrupts
        4 => {
            fw.num.writeMasked(
                u14,
                &self.dacrate,
                @truncate(value),
                @truncate(mask),
            );

            fw.log.debug("AI_DACRATE: {}", .{self.dacrate});
        },
        5 => {
            fw.num.writeMasked(
                u4,
                &self.bitrate,
                @truncate(value),
                @truncate(mask),
            );

            fw.log.debug("AI_BITRATE: {}", .{self.bitrate});
        },
        else => fw.log.panic("Unmapped AI register write: {X:08} <= {X:08}", .{ address, value }),
    }
}

const Status = packed struct(u32) {
    full_0: bool = false,
    count: u14 = 0,
    __0: u1 = 0,
    bc: bool = false,
    __1: u2 = 0,
    wc: bool = false,
    __2: u5 = 0b10001,
    enabled: bool = false,
    __3: u4 = 0,
    busy: bool = false,
    full_31: bool = false,
};
