const std = @import("std");
const fw = @import("framework");
const Ppu = @import("../Ppu.zig");

const attr_table: [4]u16 = .{ 0x0000, 0x5555, 0xaaaa, 0xffff };

pub const State = struct {
    name_latch: u8 = 0,
    attr_latch: u2 = 0,
    chr_latch: u8 = 0,
    attr: u32 = 0,
    chr_low: u16 = 0,
    chr_high: u16 = 0,
};

pub fn copyScrollX(ppu: *Ppu) void {
    ppu.address.coarse_x = ppu.tmp_address.coarse_x;
    ppu.address.name_table_x = ppu.tmp_address.name_table_x;
    fw.log.trace("VRAM Address (Copy Scroll X): {X:04}", .{ppu.address.get()});
}

pub fn copyScrollY(ppu: *Ppu) void {
    ppu.address.coarse_y = ppu.tmp_address.coarse_y;
    ppu.address.name_table_y = ppu.tmp_address.name_table_y;
    ppu.address.fine_y = ppu.tmp_address.fine_y;
    fw.log.trace("VRAM Address (Copy Scroll Y): {X:04}", .{ppu.address.get()});
}

pub fn incrementScrollX(ppu: *Ppu) void {
    ppu.address.coarse_x +%= 1;

    if (ppu.address.coarse_x == 0) {
        @branchHint(.unlikely);
        ppu.address.name_table_x ^= 1;
    }
}

pub fn incrementScrollY(ppu: *Ppu) void {
    ppu.address.fine_y +%= 1;

    if (ppu.address.fine_y == 0) {
        @branchHint(.unlikely);
        ppu.address.coarse_y +%= 1;

        if (ppu.address.coarse_y == 30) {
            @branchHint(.unlikely);
            ppu.address.coarse_y = 0;
            ppu.address.name_table_y ^= 1;
        }
    }

    fw.log.trace("VRAM Address (Increment Scroll Y): {X:04}", .{ppu.address.get()});
}

pub fn loadTiles(ppu: *Ppu) void {
    ppu.bg.attr <<= 2;
    ppu.bg.chr_low <<= 1;
    ppu.bg.chr_high <<= 1;

    const cartridge = &ppu.getDevice().cartridge;

    switch (@as(u3, @truncate(ppu.dot))) {
        0 => cartridge.setVramAddress(nameAddress(ppu)),
        1 => ppu.bg.name_latch = cartridge.readVram(),
        2 => cartridge.setVramAddress(attrAddress(ppu)),
        3 => {
            const value = cartridge.readVram();
            const shift = ((ppu.address.coarse_y & 2) << 1) | (ppu.address.coarse_x & 2);
            ppu.bg.attr_latch = @truncate(value >> @intCast(shift));
        },
        4 => cartridge.setVramAddress(chrAddress(ppu)),
        5 => ppu.bg.chr_latch = cartridge.readVram(),
        6 => cartridge.setVramAddress(chrAddress(ppu) | 8),
        7 => {
            ppu.bg.attr = (ppu.bg.attr & 0xffff_0000) | attr_table[ppu.bg.attr_latch];
            ppu.bg.chr_low = (ppu.bg.chr_low & 0xff00) | ppu.bg.chr_latch;
            ppu.bg.chr_high = (ppu.bg.chr_high & 0xff00) | cartridge.readVram();
            incrementScrollX(ppu);
        },
    }
}

pub fn loadExtra(ppu: *Ppu) void {
    const cartridge = &ppu.getDevice().cartridge;

    switch (@as(u1, @truncate(ppu.dot))) {
        0 => cartridge.setVramAddress(nameAddress(ppu)),
        1 => ppu.bg.name_latch = cartridge.readVram(),
    }
}

pub fn render(ppu: *Ppu) u5 {
    if (!ppu.mask.bg_enable) {
        return 0;
    }

    if (!ppu.mask.bg_show_left and ppu.dot < 8) {
        return 0;
    }

    const shift = @as(u4, 15) - ppu.fine_x;
    const low: u1 = @truncate(ppu.bg.chr_low >> shift);
    const high: u1 = @truncate(ppu.bg.chr_high >> shift);
    const pixel_value = (@as(u2, high) << 1) | low;

    if (pixel_value == 0) {
        return 0;
    }

    const palette_index: u2 = @truncate(ppu.bg.attr >> (@as(u5, shift) << 1));

    return (@as(u5, palette_index) << 2) | pixel_value;
}

pub fn nameAddress(ppu: *Ppu) u15 {
    return 0x2000 | (ppu.address.get() & 0x0fff);
}

pub fn attrAddress(ppu: *Ppu) u15 {
    return 0x23c0 |
        (@as(u15, ppu.address.name_table_y) << 11) |
        (@as(u15, ppu.address.name_table_x) << 10) |
        (@as(u15, ppu.address.coarse_y >> 2) << 3) |
        (ppu.address.coarse_x >> 2);
}

fn chrAddress(ppu: *Ppu) u15 {
    return (@as(u15, ppu.ctrl.bg_chr_table) << 12) |
        (@as(u15, ppu.bg.name_latch) << 4) |
        ppu.address.fine_y;
}
