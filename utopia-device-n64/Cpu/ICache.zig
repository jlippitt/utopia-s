const std = @import("std");
const fw = @import("framework");
const Core = @import("../Cpu.zig");
const Cp0 = @import("./Cp0.zig");

const size = 512;

const Entry = struct {
    instr: *const Core.Instruction = Core.decode(0),
    word: u32 = 0,
};

const Line = struct {
    valid: bool = false,
    p_tag: u20 = 0,
    data: [8]Entry = @splat(.{}),
};

const Self = @This();

lines: *[size]Line,

pub fn init(arena: *std.heap.ArenaAllocator) error{OutOfMemory}!Self {
    const lines = try arena.allocator().alloc(Line, size);

    for (lines) |*line| {
        line.* = .{};
    }

    return .{
        .lines = lines[0..size],
    };
}

pub fn get(self: *Self, vaddr: u32, paddr: u32) Entry {
    const index: u9 = @truncate(vaddr >> 5);
    const line = &self.lines[index];
    const p_tag: u20 = @truncate(paddr >> 12);

    if (!line.valid or p_tag != line.p_tag) {
        @branchHint(.unlikely);
        line.p_tag = p_tag;
        line.valid = true;

        const device = self.getCore().getDevice();
        const base_address = paddr & ~@as(u32, 0x1f);

        for (0..8) |word_index| {
            const offset = @as(u32, @intCast(word_index)) << 2;
            const word = device.read(base_address | offset);

            line.data[word_index] = .{
                .instr = Core.decode(word),
                .word = word,
            };
        }

        fw.log.trace("ICache Reload: {X:08}", .{base_address});
    }

    return line.data[@as(u3, @truncate(vaddr >> 2))];
}

pub fn invalidate(self: *Self, vaddr: u32) void {
    const index: u9 = @truncate(vaddr >> 5);
    const line = &self.lines[index];
    line.valid = false;
    fw.log.trace("ICache Invalidate: {}", .{index});
}

pub fn indexStoreTag(self: *Self, vaddr: u32, tag_lo: Cp0.TagLo) void {
    const index: u9 = @truncate(vaddr >> 5);
    const line = &self.lines[index];
    line.valid = (tag_lo.p_state & 0b10) != 0;
    line.p_tag = tag_lo.p_tag_lo;
    fw.log.trace("ICache Index Store Tag: {} <= {any}", .{ index, tag_lo });
}

pub fn hitInvalidate(self: *Self, vaddr: u32, paddr: u32) void {
    const index: u9 = @truncate(vaddr >> 5);
    const line = &self.lines[index];
    const p_tag: u20 = @truncate(paddr >> 12);

    if (p_tag == line.p_tag) {
        line.valid = false;
    }

    fw.log.trace("ICache Hit Invalidate: {}", .{index});
}

fn getCore(self: *Self) *Core {
    return @alignCast(@fieldParentPtr("icache", self));
}
