const std = @import("std");
const Device = @import("./Device.zig");
const fw = @import("framework");

const pif_size = 0x800;
const pif_ram_begin = 0x7c0;
const pif_ram_size = pif_size - pif_ram_begin;

const Self = @This();

pifdata: *align(4) [pif_size]u8,
pif_rom_locked: bool = false,
dram_addr: u24 = 0,
status: Status = .{},

pub fn init(pifdata: []align(4) u8, cic_seed: u32) Self {
    // Command byte should be zero at reset
    pifdata[0x7ff] = 0;

    // CIC seed should be present at reset
    fw.mem.writeBe(u32, pifdata, 0x7e4, cic_seed);

    return .{
        .pifdata = pifdata[0..pif_size],
    };
}

pub fn read(self: *Self, address: u32) u32 {
    return switch (@as(u4, @truncate(address >> 2))) {
        0 => self.dram_addr,
        6 => blk: {
            self.status.interrupt = self.getDeviceConst().mi.hasInterrupt(.si);
            break :blk @bitCast(self.status);
        },
        else => fw.log.panic("Unmapped SI register read: {X:08}", .{address}),
    };
}

pub fn write(self: *Self, address: u32, value: u32, mask: u32) void {
    switch (@as(u4, @truncate(address >> 2))) {
        0 => {
            fw.num.writeMasked(u24, &self.dram_addr, @truncate(value), @truncate(mask));
            fw.log.debug("  SI_DRAM_ADDR: {X:08}", .{self.dram_addr});
        },
        1 => self.transferDma(.read, @truncate(value & mask & 0x7fc)),
        4 => self.transferDma(.write, @truncate(value & mask & 0x7fc)),
        6 => self.getDevice().mi.clearInterrupt(.si),
        else => fw.log.panic("Unmapped SI register write: {X:08} <= {X:08}", .{ address, value }),
    }
}

pub fn readPif(self: *Self, address: u32) u32 {
    const index: u32 = address & 0x000f_fffc;

    if (index < pif_ram_begin and self.pif_rom_locked) {
        @branchHint(.unlikely);
        fw.log.warn("Read from locked PIF ROM area: {X:08}", .{address});
        return 0;
    }

    if (index >= pif_size) {
        @branchHint(.unlikely);
        fw.log.warn("PIF read out of range: {X:08}", .{address});
        return 0;
    }

    return fw.mem.readBe(u32, self.pifdata, index);
}

pub fn writePif(self: *Self, address: u32, value: u32, mask: u32) void {
    const index: u32 = address & 0x000f_fffc;

    if (index < pif_ram_begin) {
        @branchHint(.unlikely);
        fw.log.warn("Write to PIF ROM area: {X:08} <= {X:08}", .{ address, value });
        return;
    }

    if (index >= pif_size) {
        @branchHint(.unlikely);
        fw.log.warn("PIF write out of range: {X:08} <= {X:08}", .{ address, value });
        return;
    }

    fw.mem.writeMaskedBe(u32, self.pifdata, index, value, mask);

    self.processPifCommand();

    self.getDevice().mi.raiseInterrupt(.si);
}

fn transferDma(self: *Self, comptime direction: DmaDirection, pif_addr: u11) void {
    const len = pif_ram_size;

    if ((self.dram_addr & 7) != 0) {
        fw.log.unimplemented("SI DMA with misaligned DRAM address: {X:08}", .{
            self.dram_addr,
        });
    }

    if (pif_addr != 0x7c0) {
        fw.log.unimplemented("SI DMA with non-PIF RAM address: {X:03}", .{
            pif_addr,
        });
    }

    switch (comptime direction) {
        .read => {
            fw.log.todo("Execute joybus program", .{});

            const rdram = self.getDevice().rdram;

            @memcpy(rdram[self.dram_addr..][0..len], self.pifdata[pif_addr..][0..len]);

            fw.log.debug("SI DMA: {} bytes read from PIF:{X:03} to {X:08}", .{
                len,
                pif_addr,
                self.dram_addr,
            });
        },
        .write => {
            const rdram = self.getDeviceConst().rdram;

            @memcpy(self.pifdata[pif_addr..][0..len], rdram[self.dram_addr..][0..len]);

            fw.log.debug("SI DMA: {} bytes written from {X:08} to PIF:{X:03}", .{
                len,
                self.dram_addr,
                pif_addr,
            });

            self.processPifCommand();
        },
    }

    self.dram_addr +%= len;

    self.getDevice().mi.raiseInterrupt(.si);
}

fn getDevice(self: *Self) *Device {
    return @alignCast(@fieldParentPtr("si", self));
}

fn getDeviceConst(self: *Self) *const Device {
    return @alignCast(@fieldParentPtr("si", self));
}

fn processPifCommand(self: *Self) void {
    const cmd = self.pifdata[0x7ff];

    if ((cmd & 0x7f) == 0) {
        return;
    }

    var result: u8 = 0;

    if ((cmd & 0x01) != 0) {
        fw.log.todo("Joybus queries", .{});
    }

    if ((cmd & 0x02) != 0) {
        fw.log.todo("PIF challenge/response", .{});
    }

    if ((cmd & 0x10) != 0) {
        self.pif_rom_locked = true;
        fw.log.trace("PIF ROM Locked: {}", .{self.pif_rom_locked});
    }

    if ((cmd & 0x20) != 0) {
        fw.log.trace("PIF Acquire Checksum", .{});
        result |= 0x80;
    }

    self.pifdata[0x7ff] = result;
}

const Status = packed struct(u32) {
    dma_busy: bool = false,
    io_busy: bool = false,
    read_pending: bool = false,
    dma_error: bool = false,
    pch_state: u4 = 0,
    dma_state: u4 = 0,
    interrupt: bool = false,
    __: u19 = 0,
};

const DmaDirection = enum {
    read,
    write,
};
