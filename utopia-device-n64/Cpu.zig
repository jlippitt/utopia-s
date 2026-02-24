const fw = @import("framework");
const log = fw.log;

const Self = @This();

const cold_reset_vector = 0xbfc0_0000;

pub const Bus = struct {
    read: fn (self: *Self, address: u32) u32,
    write: fn (self: *Self, address: u32, value: u32, mask: u32) void,
};

pc: u32 = cold_reset_vector,
target_pc: u32 = 0,
regs: [32]u64 = @splat(0),

pub fn init() Self {
    return .{};
}

pub fn step(self: *Self, comptime bus: Bus) void {
    const word = bus.read(self, self.mapAddress(self.pc) orelse return);

    switch (@as(u6, @truncate(word >> 26))) {
        else => |opcode| log.todo("CPU opcode: {o:02}", .{opcode}),
    }
}

pub fn mapAddress(self: *Self, paddr: u32) ?u32 {
    _ = self;

    if ((paddr & 0xc000_0000) == 0x8000_0000) {
        return paddr & 0x1fff_ffff;
    }

    log.todo("TLB lookups", .{});
}
