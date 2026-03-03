const fw = @import("framework");
const Core = @import("../../Cpu.zig");

const mask_filter = 0xaaa;

pub const Index = packed struct(u32) {
    index: u6 = 0,
    __: u25 = 0,
    probe_failed: bool = false,
};

pub const EntryLo = packed struct(u64) {
    global: bool = false,
    valid: bool = false,
    dirty: bool = false,
    cache: u3 = 0,
    pfn: u20 = 0,
    __: u38 = 0,
};

pub const EntryHi = packed struct(u64) {
    asid: u8 = 0,
    __0: u4 = 0,
    global: bool = false,
    vpn2: u27 = 0,
    __1: u22 = 0,
    region: u2 = 0,
};

pub const PageMask = packed struct(u64) {
    __0: u13 = 0,
    mask: u12 = 0,
    __1: u39 = 0,
};

const Entry = struct {
    page_mask: PageMask = .{},
    entry_hi: EntryHi = .{},
    entry_lo: [2]EntryLo = @splat(.{}),
};

const Self = @This();

entries: [32]Entry = @splat(.{}),

pub fn init() Self {
    return .{};
}

fn write(self: *Self, index: u5, regs: Entry) void {
    const filtered = regs.page_mask.mask & mask_filter;
    const mask = filtered | (filtered >> 1);

    var entry = &self.entries[index];

    entry.page_mask = .{
        .mask = mask,
    };

    entry.entry_hi = .{
        .asid = regs.entry_hi.asid,
        .global = regs.entry_lo[0].global or regs.entry_lo[1].global,
        .vpn2 = regs.entry_hi.vpn2 & ~@as(u27, mask),
        .region = regs.entry_hi.region,
    };

    for (0..1) |id| {
        // Note: Fields are explicitly copied to avoid copying bits that aren't assigned to a
        // named struct field. This is important as some of those bits are writable on the CP0
        // register but shouldn't be carried over to the TLB entry.
        entry.entry_lo[id] = .{
            .global = regs.entry_lo[id].global,
            .valid = regs.entry_lo[id].valid,
            .dirty = regs.entry_lo[id].dirty,
            .cache = regs.entry_lo[id].cache,
            .pfn = regs.entry_lo[id].pfn,
        };
    }

    fw.log.trace("TLB Entry {}: {any}", .{ index, entry.* });
}

fn probe(self: *const Self, entry_hi: EntryHi) Index {
    for (self.entries, 0..) |entry, index| {
        const lhs = entry_hi;
        const rhs = entry.entry_hi;
        const mask: u27 = entry.page_mask.mask;

        if (lhs.region == rhs.region and
            (lhs.vpn2 & ~mask) == (rhs.vpn2 & ~mask) and
            (rhs.global or lhs.asid == rhs.asid))
        {
            return .{
                .index = @intCast(index),
                .probe_failed = false,
            };
        }
    }

    return .{
        .index = 0,
        .probe_failed = true,
    };
}

pub fn tlbwi(core: *Core, word: u32) void {
    _ = word;

    fw.log.trace("{X:08}: TLBWI", .{core.pc});

    const index: u5 = @truncate(core.cp0.index.index);

    core.cp0.tlb.write(index, .{
        .page_mask = core.cp0.page_mask,
        .entry_hi = core.cp0.entry_hi,
        .entry_lo = core.cp0.entry_lo,
    });
}

pub fn tlbp(core: *Core, word: u32) void {
    _ = word;

    fw.log.trace("{X:08}: TLBP", .{core.pc});

    core.cp0.setIndex(core.cp0.tlb.probe(core.cp0.entry_hi));
}
