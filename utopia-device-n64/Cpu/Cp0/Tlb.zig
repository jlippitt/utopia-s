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

const Self = @This();

pub fn init() Self {
    return .{};
}
