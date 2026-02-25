const fw = @import("framework");

const Self = @This();

rom: []align(8) const u8,
status: Status = .{},
bsd_dom1: BsdDom = .{},
bsd_dom2: BsdDom = .{},

pub fn init(rom: []align(8) const u8) Self {
    return .{
        .rom = rom,
    };
}

pub fn read(self: *Self, address: u32) u32 {
    return switch (@as(u4, @truncate(address >> 2))) {
        4 => @bitCast(self.status),
        5 => self.bsd_dom1.lat,
        6 => self.bsd_dom1.pwd,
        7 => self.bsd_dom1.pgs,
        8 => self.bsd_dom1.rls,
        9 => self.bsd_dom2.lat,
        10 => self.bsd_dom2.pwd,
        11 => self.bsd_dom2.pgs,
        12 => self.bsd_dom2.rls,
        else => fw.log.panic("Unmapped PI register read: {X:08}", .{address}),
    };
}

pub fn write(self: *Self, address: u32, value: u32, mask: u32) void {
    switch (@as(u4, @truncate(address >> 2))) {
        4 => {}, // TODO: PI interrupts
        5 => {
            fw.num.writeMasked(comptime u8, &self.bsd_dom1.lat, @truncate(value), @truncate(mask));
            fw.log.trace("BSD_DOM1_LAT: {}", .{self.bsd_dom1.lat});
        },
        6 => {
            fw.num.writeMasked(comptime u8, &self.bsd_dom1.pwd, @truncate(value), @truncate(mask));
            fw.log.trace("BSD_DOM1_PWD: {}", .{self.bsd_dom1.pwd});
        },
        7 => {
            fw.num.writeMasked(comptime u4, &self.bsd_dom1.pgs, @truncate(value), @truncate(mask));
            fw.log.trace("BSD_DOM1_PGS: {}", .{self.bsd_dom1.pgs});
        },
        8 => {
            fw.num.writeMasked(comptime u2, &self.bsd_dom1.rls, @truncate(value), @truncate(mask));
            fw.log.trace("BSD_DOM1_RLS: {}", .{self.bsd_dom1.rls});
        },
        9 => {
            fw.num.writeMasked(comptime u8, &self.bsd_dom2.lat, @truncate(value), @truncate(mask));
            fw.log.trace("BSD_DOM2_LAT: {}", .{self.bsd_dom2.lat});
        },
        10 => {
            fw.num.writeMasked(comptime u8, &self.bsd_dom2.pwd, @truncate(value), @truncate(mask));
            fw.log.trace("BSD_DOM2_PWD: {}", .{self.bsd_dom2.pwd});
        },
        11 => {
            fw.num.writeMasked(comptime u4, &self.bsd_dom2.pgs, @truncate(value), @truncate(mask));
            fw.log.trace("BSD_DOM2_PGS: {}", .{self.bsd_dom2.pgs});
        },
        12 => {
            fw.num.writeMasked(comptime u2, &self.bsd_dom2.rls, @truncate(value), @truncate(mask));
            fw.log.trace("BSD_DOM2_RLS: {}", .{self.bsd_dom2.rls});
        },
        else => fw.log.panic("Unmapped PI register write: {X:08} <= {X:08}", .{ address, value }),
    }
}

pub fn readRom(self: *const Self, address: u32) u32 {
    const index = address & 0x0fff_fffc;

    if (index >= self.rom.len) {
        fw.log.warn("Cartridge ROM read out of range: {X:08}", .{address});
        return 0;
    }

    return fw.mem.readBe(u32, self.rom, index);
}

const Status = packed struct(u32) {
    dma_busy: bool = false,
    io_busy: bool = false,
    dma_error: bool = false,
    interrupt: bool = false,
    __: u28 = 0,
};

const BsdDom = struct {
    lat: u8 = 0,
    pwd: u8 = 0,
    pgs: u4 = 0,
    rls: u2 = 0,
};
