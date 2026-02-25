const std = @import("std");
const fw = @import("framework");

const mem_size = 8192;

const Self = @This();

mem: *align(16) [mem_size]u8,
status: Status = .{},
pc: u12 = 0,

pub fn init(allocator: std.mem.Allocator) !Self {
    const mem = try allocator.alignedAlloc(u8, .@"16", mem_size);

    return .{
        .mem = mem[0..mem_size],
    };
}

pub fn read(self: *Self, address: u32) u32 {
    if ((address & 0x000c_0000) == 0) {
        return fw.mem.readBe(u32, self.mem, address & 0x1fff);
    }

    if ((address & 0x000c_0000) == 0x0004_0000) {
        return self.readRegister(@truncate(address >> 2));
    }

    if (address == 0x0008_0000) {
        return self.pc;
    }

    fw.log.panic("Unmapped RSP read: {X:08}", .{address});
}

pub fn write(self: *Self, address: u32, value: u32, mask: u32) void {
    if ((address & 0x000c_0000) == 0) {
        fw.mem.writeBe(u32, self.mem, address & 0x1fff, value, mask);
        return;
    }

    if ((address & 0x000c_0000) == 0x0004_0000) {
        self.writeRegister(@truncate(address >> 2), value, mask);
        return;
    }

    if (address == 0x0008_0000) {
        fw.num.writeWithMask(u12, &self.pc, @truncate(value), @truncate(mask));
        fw.log.debug("RSP PC: {X:08}", .{self.pc});
    }

    fw.log.panic("Unmapped RSP write: {X:08} <= {X:08}", .{ address, value });
}

pub fn readRegister(self: *Self, index: u3) u32 {
    return switch (index) {
        4 => @bitCast(self.status),
        else => fw.log.panic("Unmapped RSP register read: {}", .{index}),
    };
}

pub fn writeRegister(self: *Self, index: u3, value: u32, mask: u32) void {
    _ = self;
    _ = mask;

    switch (index) {
        else => fw.log.panic("Unmapped RSP register write: {} <= {X:08}", .{ index, value }),
    }
}

const Status = packed struct(u32) {
    halted: bool = true,
    broke: bool = false,
    dma_busy: bool = false,
    dma_full: bool = false,
    io_busy: bool = false,
    sstep: bool = false,
    intbreak: bool = false,
    sig0: bool = false,
    sig1: bool = false,
    sig2: bool = false,
    sig3: bool = false,
    sig4: bool = false,
    sig5: bool = false,
    sig6: bool = false,
    sig7: bool = false,
    __: u17 = 0,
};
