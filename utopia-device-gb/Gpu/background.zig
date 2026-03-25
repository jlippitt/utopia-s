const std = @import("std");
const Gpu = @import("../Gpu.zig");

pub const State = struct {
    const Self = @This();

    load_step: u3 = 0,
    fifo_len: u8 = 0,
    tile_number: u5 = 0,
    fine_x: u3 = 0,
    tile: Gpu.Tile = .{},
    window_active_y: bool = false,
    window_active_x: bool = false,
    window_pos_y: u8 = 0,
    window_pos_x: u8 = 0,

    pub fn beginFrame(self: *Self) void {
        self.window_active_y = false;
    }

    pub fn restartLoad(self: *Self) void {
        self.load_step = 0;
    }

    pub fn pushTile(self: *Self, tile: Gpu.Tile) void {
        self.tile = tile;
        self.fifo_len = 8;
        self.load_step = 0;
        self.tile_number +%= 1;
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

pub fn beginLine(gpu: *Gpu) void {
    gpu.bg.load_step = 0;
    gpu.bg.fifo_len = 0;
    gpu.bg.tile_number = 0;
    gpu.bg.fine_x = @truncate(gpu.scroll_x);
    gpu.bg.window_active_x = false;

    if (gpu.bg.window_active_y) {
        gpu.bg.window_pos_y += 1;
    } else if (gpu.line == gpu.window_y) {
        gpu.bg.window_active_y = true;
        gpu.bg.window_pos_y = 0;
    }

    if (gpu.bg.window_active_y) {
        gpu.bg.window_pos_x = gpu.window_x -% 7;
    } else {
        gpu.bg.window_pos_x = std.math.maxInt(u8);
    }
}

pub fn loadTiles(gpu: *Gpu) void {
    if (gpu.dot == gpu.bg.window_pos_x and gpu.bg.window_active_y and !gpu.bg.window_active_x) {
        @branchHint(.unlikely);
        gpu.bg.window_active_x = true;
        gpu.bg.load_step = 0;
        gpu.bg.fifo_len = 0;
        gpu.bg.tile_number = 0;
        gpu.bg.fine_x = @as(u3, @truncate(gpu.bg.window_pos_x)) ^ 7;
    }

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
    var coarse_x = gpu.bg.tile_number;

    const tile_map = if (gpu.bg.window_active_x and gpu.ctrl.window_enable) blk: {
        @branchHint(.unlikely);
        break :blk gpu.ctrl.window_tile_map;
    } else blk: {
        coarse_x +%= @truncate(gpu.scroll_x >> 3);
        break :blk gpu.ctrl.bg_tile_map;
    };

    return 0x1800 |
        (@as(u13, tile_map) << 10) |
        (@as(u13, coarse_y) << 5) |
        @as(u13, coarse_x);
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
    if (gpu.bg.window_active_x and gpu.ctrl.window_enable) {
        @branchHint(.unlikely);
        return gpu.bg.window_pos_y;
    }

    return gpu.scroll_y +% gpu.line;
}
