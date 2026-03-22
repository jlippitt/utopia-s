const std = @import("std");
const fw = @import("framework");
const Device = @import("./Device.zig");

const sram_size = 32768;

const Self = @This();

rom: []align(8) const u8,
sram: []align(4) u8,
sram_dirty: bool = false,
dram_addr: u24 = 0,
cart_addr: u32 = 0,
status: Status = .{},
bsd_dom1: BsdDom = .{},
bsd_dom2: BsdDom = .{},

pub fn init(
    arena: *std.heap.ArenaAllocator,
    vfs: fw.Vfs,
    rom: []align(8) const u8,
) fw.Vfs.Error!Self {
    const sram = try arena.allocator().alignedAlloc(u8, .@"4", sram_size);
    _ = try vfs.readSave(arena.allocator(), "sram", sram);

    return .{
        .rom = rom,
        .sram = sram,
    };
}

pub fn save(self: *Self, allocator: std.mem.Allocator, vfs: fw.Vfs) fw.Vfs.Error!void {
    if (!self.sram_dirty) {
        return;
    }

    try vfs.writeSave(allocator, "sram", self.sram);
    self.sram_dirty = false;
}

pub fn read(self: *Self, address: u32) u32 {
    return switch (@as(u4, @truncate(address >> 2))) {
        0 => self.dram_addr,
        1 => self.cart_addr,
        2, 3 => 0x7f,
        4 => blk: {
            self.status.interrupt = self.getDeviceConst().mi.hasInterrupt(.pi);
            break :blk @bitCast(self.status);
        },
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
        0 => {
            fw.num.writeMasked(
                u24,
                &self.dram_addr,
                @truncate(value),
                @truncate(mask & ~@as(u32, 1)),
            );

            fw.log.trace("PI_DRAM_ADDR: {X:08}", .{self.dram_addr});
        },
        1 => {
            fw.num.writeMasked(u32, &self.cart_addr, value, mask & ~@as(u32, 1));
            fw.log.trace("PI_CART_ADDR: {X:08}", .{self.cart_addr});
        },
        2 => self.transferDma(.read, @truncate(value & mask)),
        3 => self.transferDma(.write, @truncate(value & mask)),
        4 => if (fw.num.bit(value & mask, 1)) {
            self.getDevice().mi.clearInterrupt(.pi);
        },
        5 => {
            fw.num.writeMasked(u8, &self.bsd_dom1.lat, @truncate(value), @truncate(mask));
            fw.log.trace("PI_BSD_DOM1_LAT: {}", .{self.bsd_dom1.lat});
        },
        6 => {
            fw.num.writeMasked(u8, &self.bsd_dom1.pwd, @truncate(value), @truncate(mask));
            fw.log.trace("PI_BSD_DOM1_PWD: {}", .{self.bsd_dom1.pwd});
        },
        7 => {
            fw.num.writeMasked(u4, &self.bsd_dom1.pgs, @truncate(value), @truncate(mask));
            fw.log.trace("PI_BSD_DOM1_PGS: {}", .{self.bsd_dom1.pgs});
        },
        8 => {
            fw.num.writeMasked(u2, &self.bsd_dom1.rls, @truncate(value), @truncate(mask));
            fw.log.trace("PI_BSD_DOM1_RLS: {}", .{self.bsd_dom1.rls});
        },
        9 => {
            fw.num.writeMasked(u8, &self.bsd_dom2.lat, @truncate(value), @truncate(mask));
            fw.log.trace("PI_BSD_DOM2_LAT: {}", .{self.bsd_dom2.lat});
        },
        10 => {
            fw.num.writeMasked(u8, &self.bsd_dom2.pwd, @truncate(value), @truncate(mask));
            fw.log.trace("PI_BSD_DOM2_PWD: {}", .{self.bsd_dom2.pwd});
        },
        11 => {
            fw.num.writeMasked(u4, &self.bsd_dom2.pgs, @truncate(value), @truncate(mask));
            fw.log.trace("PI_BSD_DOM2_PGS: {}", .{self.bsd_dom2.pgs});
        },
        12 => {
            fw.num.writeMasked(u2, &self.bsd_dom2.rls, @truncate(value), @truncate(mask));
            fw.log.trace("PI_BSD_DOM2_RLS: {}", .{self.bsd_dom2.rls});
        },
        else => fw.log.panic("Unmapped PI register write: {X:08} <= {X:08}", .{ address, value }),
    }
}

pub fn readSram(self: *const Self, address: u32) u32 {
    const index = address & 0x07ff_fffc;

    if (index >= self.sram.len) {
        fw.log.warn("SRAM read out of range: {X:08}", .{address});
        return 0;
    }

    return fw.mem.readBe(u32, self.sram, index);
}

pub fn writeSram(self: *Self, address: u32, value: u32) void {
    const index = address & 0x07ff_fffc;

    if (index >= self.sram.len) {
        fw.log.warn("SRAM write out of range: {X:08} <= {X:08}", .{ address, value });
        return;
    }

    fw.mem.writeBe(u32, self.sram, index, value);
    self.sram_dirty = true;
}

pub fn readRom(self: *const Self, address: u32) u32 {
    const index = address & 0x0fff_fffc;

    if (index >= self.rom.len) {
        fw.log.warn("ROM read out of range: {X:08}", .{address});
        return 0;
    }

    return fw.mem.readBe(u32, self.rom, index);
}

fn transferDma(self: *Self, comptime direction: DmaDirection, raw_len: u24) void {
    const len = (raw_len + 1) & ~@as(u24, 1);

    switch (comptime direction) {
        .read => {
            const src = self.getDeviceConst().rdram[self.dram_addr..][0..len];

            if (self.cart_addr >= 0x1000_0000) {
                fw.log.warn("PI DMA read targeting ROM area: {X:08}", .{self.cart_addr});
            } else if (self.cart_addr >= 0x0800_0000) {
                @memcpy(self.sram[(self.cart_addr & 0x07ff_ffff)..][0..len], src);
                self.sram_dirty = true;
            } else {
                // TODO: 64DD
            }

            fw.log.debug("PI DMA: {} bytes read from {X:08} to {X:08}", .{
                len,
                self.dram_addr,
                self.cart_addr,
            });
        },
        .write => {
            const dst = self.getDevice().rdram[self.dram_addr..][0..len];

            if (self.cart_addr >= 0x1000_0000) {
                @memcpy(dst, self.rom[(self.cart_addr & 0x0fff_ffff)..][0..len]);
            } else if (self.cart_addr >= 0x0800_0000) {
                @memcpy(dst, self.sram[(self.cart_addr & 0x07ff_ffff)..][0..len]);
            } else {
                // TODO: 64DD
                // Just write zeroes for now
                @memset(dst, 0);
            }

            fw.log.debug("PI DMA: {} bytes written from {X:08} to {X:08}", .{
                len,
                self.cart_addr,
                self.dram_addr,
            });
        },
    }

    self.dram_addr +%= len;
    self.cart_addr +%= len;

    self.getDevice().mi.raiseInterrupt(.pi);
}

fn getDevice(self: *Self) *Device {
    return @alignCast(@fieldParentPtr("pi", self));
}

fn getDeviceConst(self: *Self) *const Device {
    return @alignCast(@fieldParentPtr("pi", self));
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

const DmaDirection = enum {
    read,
    write,
};
