const std = @import("std");
const fw = @import("framework");

const pif_size = 0x800;
const pif_ram_begin = 0x7c0;

const Self = @This();

pifdata: *align(4) [pif_size]u8,
pif_rom_locked: bool = false,

pub fn init(pifdata: []align(4) u8) Self {
    // Command byte should be zero at reset
    pifdata[0x7ff] = 0;

    return .{
        .pifdata = pifdata[0..pif_size],
    };
}

pub fn read(self: *Self, address: u32) u32 {
    _ = self;

    return switch (@as(u4, @truncate(address >> 2))) {
        else => fw.log.panic("Unmapped SI register read: {X:08}", .{address}),
    };
}

pub fn write(self: *Self, address: u32, value: u32, mask: u32) void {
    _ = self;
    _ = mask;

    switch (@as(u4, @truncate(address >> 2))) {
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

    if (index < pif_size) {
        @branchHint(.unlikely);
        fw.log.warn("PIF write out of range: {X:08} <= {X:08}", .{ address, value });
        return;
    }

    fw.mem.writeBe(u32, self.pifdata, index, value, mask);

    if (index == 0x7fc) {
        self.processPifCommand();
    }
}

fn processPifCommand(self: *Self) void {
    const cmd = self.pifdata[0x7ff];
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

    self.pifdata[0x7ff] = 0;
}
