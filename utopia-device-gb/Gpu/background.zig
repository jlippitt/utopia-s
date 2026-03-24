const std = @import("std");
const Gpu = @import("../Gpu.zig");

pub const State = struct {
    const Self = @This();

    load_step: u3 = 0,
    fifo_len: u8 = 0,
    coarse_x: u5 = 0,
    fine_x: u3 = 0,
    tile: Gpu.Tile = .{},

    pub fn beginLine(self: *Self, scroll_x: u8) void {
        self.load_step = 0;
        self.fifo_len = 0;
        self.coarse_x = @truncate(scroll_x >> 3);
        self.fine_x = @truncate(scroll_x);
    }

    pub fn restartLoad(self: *Self) void {
        self.load_step = 0;
    }

    pub fn pushTile(self: *Self, tile: Gpu.Tile) void {
        self.tile = tile;
        self.fifo_len = 8;
        self.load_step = 0;
        self.coarse_x +%= 1;
    }

    pub fn popPixel(self: *Self) ?u2 {
        if (self.fifo_len == 0) {
            return null;
        }

        if (self.fine_x > 0) {
            self.fine_x -= 1;
            return null;
        }

        self.fifo_len -= 1;

        self.tile.chr_low = std.math.rotl(u8, self.tile.chr_low, 1);
        self.tile.chr_high = std.math.rotl(u8, self.tile.chr_high, 1);

        const chr_low: u1 = @truncate(self.tile.chr_low);
        const chr_high: u1 = @truncate(self.tile.chr_high);

        return (@as(u2, chr_high) << 1) | chr_low;
    }
};

pub fn loadTiles(gpu: *Gpu) void {
    switch (gpu.bg.load_step) {
        0, 2, 4 => gpu.bg.load_step += 1,
        1 => {
            gpu.name_latch = gpu.vram[nameAddress(gpu)];
            gpu.bg.load_step += 1;
        },
        3 => {
            gpu.tile_latch.chr_low = gpu.vram[chrAddress(gpu)];
            gpu.bg.load_step += 1;
        },
        5 => {
            gpu.tile_latch.chr_high = gpu.vram[chrAddress(gpu) | 1];
            gpu.bg.load_step += 1;
        },
        6 => if (gpu.bg.fifo_len == 0) {
            gpu.bg.pushTile(gpu.tile_latch);
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

    const name: u13 = if (gpu.ctrl.bg_chr_map or gpu.name_latch >= 128)
        gpu.name_latch
    else
        @as(u13, gpu.name_latch) + 256;

    return (name << 4) | (@as(u13, fine_y) << 1);
}

fn posY(gpu: *Gpu) u8 {
    return gpu.scroll_y +% gpu.line;
}
