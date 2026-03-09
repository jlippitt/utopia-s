const std = @import("std");
const fw = @import("framework");
const Core = @import("../Cpu.zig");
const Cp0 = @import("./Cp0.zig");

const size = 512;

const Tag = packed struct(u32) {
    invalid: bool = true,
    __: u11 = 0,
    p_tag: u20 = 0,
};

const Entry = struct {
    instr: *const Core.Instruction = Core.decode(0),
    word: u32 = 0,
};

const Line = struct {
    tag: Tag = .{},
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
    const tag = paddr & 0xffff_f000;

    if (tag != @as(u32, @bitCast(line.tag))) {
        @branchHint(.unlikely);
        line.tag = @bitCast(tag);

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
    line.tag.invalid = true;
    fw.log.trace("ICache Invalidate: {}", .{index});
}

pub fn indexStoreTag(self: *Self, vaddr: u32, tag_lo: Cp0.TagLo) void {
    const index: u9 = @truncate(vaddr >> 5);
    const line = &self.lines[index];
    line.tag.invalid = (tag_lo.p_state & 0b10) == 0;
    line.tag.p_tag = tag_lo.p_tag_lo;
    fw.log.trace("ICache Index Store Tag: {} <= {any}", .{ index, tag_lo });
}

pub fn hitInvalidate(self: *Self, vaddr: u32, paddr: u32) void {
    const index: u9 = @truncate(vaddr >> 5);
    const line = &self.lines[index];
    const tag = paddr & 0xffff_f000;

    if (tag == @as(u32, @bitCast(line.tag))) {
        line.tag.invalid = true;
    }

    fw.log.trace("ICache Hit Invalidate: {}", .{index});
}

fn getCore(self: *Self) *Core {
    return @alignCast(@fieldParentPtr("icache", self));
}
