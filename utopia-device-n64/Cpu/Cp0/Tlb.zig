const std = @import("std");
const fw = @import("framework");
const Core = @import("../../Cpu.zig");

const cache_size = 0x100000;
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

pub const Entry = struct {
    page_mask: PageMask = .{},
    entry_hi: EntryHi = .{},
    entry_lo: [2]EntryLo = @splat(.{}),
};

pub const CacheEntry = packed struct(u32) {
    valid: bool = false,
    dirty: bool = false,
    cache: bool = false,
    __: u9 = 0,
    pfn: u20 = 0,
};

pub const Error = error{
    TlbModification,
    TlbMiss,
    TlbInvalid,
};

const Self = @This();

entries: [32]Entry = @splat(.{}),
cache: [2]*[cache_size]CacheEntry,

pub fn init(arena: *std.heap.ArenaAllocator) error{OutOfMemory}!Self {
    const cache: [2][]CacheEntry = .{
        try arena.allocator().alloc(CacheEntry, cache_size),
        try arena.allocator().alloc(CacheEntry, cache_size),
    };

    for (cache) |inner| {
        for (inner) |*result| {
            result.* = .{};
        }
    }

    return .{
        .cache = .{
            cache[0][0..cache_size],
            cache[1][0..cache_size],
        },
    };
}

pub fn mapAddress(self: *Self, vaddr: u32, asid: u8, store: bool) Error!struct { u32, bool } {
    const result = &self.cache[@intFromBool(store)][@as(u20, @truncate(vaddr >> 12))];

    if (result.valid) {
        @branchHint(.likely);
        return .{ (@as(u32, result.pfn) << 12) | (vaddr & 0xfff), result.cache };
    }

    for (self.entries) |entry| {
        const entry_hi = entry.entry_hi;
        const page = @as(u32, entry_hi.vpn2) << 13;
        const mask = ~@as(u32, entry.page_mask.mask) << 13;

        if (page != (vaddr & mask)) {
            continue;
        }

        if (!entry_hi.global and entry_hi.asid != asid) {
            continue;
        }

        const selector_bit = (~mask + 1) >> 1;
        const entry_lo = entry.entry_lo[@intFromBool((vaddr & selector_bit) != 0)];

        if (!entry_lo.valid) {
            return error.TlbInvalid;
        }

        const address = (@as(u32, entry_lo.pfn) << 12) | (vaddr & ~mask & ~selector_bit);
        const cache = entry_lo.cache != 0b010;
        const dirty = entry_lo.dirty;

        if (store and !dirty) {
            return error.TlbModification;
        }

        if (entry_hi.global) {
            result.* = .{
                .valid = true,
                .dirty = dirty,
                .cache = cache,
                .pfn = @truncate(address >> 12),
            };
        }

        return .{ address, cache };
    }

    return error.TlbMiss;
}

fn read(self: *const Self, index: u5) Entry {
    var entry = self.entries[index];
    entry.entry_lo[0].global = entry.entry_hi.global;
    entry.entry_lo[1].global = entry.entry_hi.global;
    entry.entry_hi.vpn2 &= ~@as(u27, entry.page_mask.mask);
    entry.entry_hi.global = false;
    return entry;
}

fn write(self: *Self, index: u5, regs: Entry) void {
    const filtered = regs.page_mask.mask & mask_filter;
    const mask = filtered | (filtered >> 1);

    var entry = &self.entries[index];

    self.invalidateCache(entry);

    entry.page_mask = .{
        .mask = mask,
    };

    entry.entry_hi = .{
        .asid = regs.entry_hi.asid,
        .global = regs.entry_lo[0].global and regs.entry_lo[1].global,
        .vpn2 = regs.entry_hi.vpn2 & ~@as(u27, mask),
        .region = regs.entry_hi.region,
    };

    for (&entry.entry_lo, regs.entry_lo) |*dst, src| {
        // Note: Fields are explicitly copied to avoid copying bits that aren't assigned to a
        // named struct field. This is important as some of those bits are writable on the CP0
        // register but shouldn't be carried over to the TLB entry.
        dst.* = .{
            .global = src.global,
            .valid = src.valid,
            .dirty = src.dirty,
            .cache = src.cache,
            .pfn = src.pfn,
        };
    }

    fw.log.trace("TLB Entry {}: {any}", .{ index, entry.* });

    self.invalidateCache(entry);
}

fn invalidateCache(self: *Self, entry: *const Entry) void {
    const start: u32 = @as(u20, @truncate(entry.entry_hi.vpn2 << 1));
    const end = start + ((@as(u20, entry.page_mask.mask) + 1) << 1);

    if (start < 0x8_0000 or end >= 0xc_0000) {
        for (start..end) |vpn| {
            self.cache[0][vpn].valid = false;
            self.cache[1][vpn].valid = false;
        }
    }
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

pub fn tlbr(core: *Core, word: u32) void {
    _ = word;
    fw.log.trace("{X:08}: TLBR", .{core.pc});
    const index: u5 = @truncate(core.cp0.index.index);
    core.cp0.setEntry(core.cp0.tlb.read(index));
}

pub fn tlbwr(core: *Core, word: u32) void {
    _ = word;

    fw.log.trace("{X:08}: TLBWR", .{core.pc});

    const index: u5 = @truncate(core.cp0.getRandom());

    core.cp0.tlb.write(index, .{
        .page_mask = core.cp0.page_mask,
        .entry_hi = core.cp0.entry_hi,
        .entry_lo = core.cp0.entry_lo,
    });
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
