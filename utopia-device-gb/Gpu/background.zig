const std = @import("std");
const Gpu = @import("../Gpu.zig");

const Tile = struct {
    chr_low: u8 = 0,
    chr_high: u8 = 0,
};

pub const State = struct {
    const Self = @This();

    active: Tile = .{},
    pending: Tile = .{},
    load_step: u3 = 0,
    name_latch: u8 = 0,
    fifo_len: u4 = 0,
    coarse_x: u5 = 0,
    fine_x: u3 = 0,

    pub fn reset(self: *Self, scroll_x: u8) void {
        self.load_step = 0;
        self.fifo_len = 0;
        self.coarse_x = @truncate(scroll_x >> 3);
        self.fine_x = @truncate(scroll_x);
    }

    pub fn popPixel(self: *Self) ?u2 {
        if (self.fifo_len == 0) {
            return null;
        }

        if (self.fine_x > 0) {
            self.fine_x -= 1;
            return null;
        }

        self.active.chr_low = std.math.rotl(u8, self.active.chr_low, 1);
        self.active.chr_high = std.math.rotl(u8, self.active.chr_high, 1);
        self.fifo_len -= 1;

        const low: u1 = @truncate(self.active.chr_low);
        const high: u1 = @truncate(self.active.chr_high);

        return (@as(u2, high) << 1) | low;
    }
};

pub fn loadTiles(gpu: *Gpu) void {
    switch (gpu.bg.load_step) {
        0, 2, 4 => gpu.bg.load_step += 1,
        1 => {
            gpu.bg.name_latch = gpu.vram[nameAddress(gpu)];
            gpu.bg.load_step += 1;
        },
        3 => {
            gpu.bg.pending.chr_low = gpu.vram[chrAddress(gpu)];
            gpu.bg.load_step += 1;
        },
        5 => {
            gpu.bg.pending.chr_high = gpu.vram[chrAddress(gpu) | 1];
            gpu.bg.load_step += 1;
        },
        6 => if (gpu.bg.fifo_len == 0) {
            gpu.bg.active = gpu.bg.pending;
            gpu.bg.fifo_len = 8;
            gpu.bg.load_step = 0;
            gpu.bg.coarse_x +%= 1;
        },
        7 => unreachable,
    }
}

fn nameAddress(gpu: *Gpu) u13 {
    const coarse_y = posY(gpu) >> 3;

    return 0x1800 |
        (@as(u13, gpu.ctrl.bg_tile_map) << 10) |
        (@as(u13, coarse_y) << 5) |
        @as(u13, gpu.bg.coarse_x);
}

fn chrAddress(gpu: *Gpu) u13 {
    const fine_y: u3 = @truncate(posY(gpu));

    const name: u13 = if (gpu.ctrl.bg_chr_map or gpu.bg.name_latch >= 128)
        gpu.bg.name_latch
    else
        @as(u13, gpu.bg.name_latch) + 256;

    return (name << 4) | (@as(u13, fine_y) << 1);
}

fn posY(gpu: *Gpu) u8 {
    return gpu.scroll_y +% gpu.line;
}
