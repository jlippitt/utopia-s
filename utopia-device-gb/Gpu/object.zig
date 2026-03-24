const std = @import("std");
const fw = @import("framework");
const Gpu = @import("../Gpu.zig");

const max_sprites_per_line = 10;

const SpriteAttributes = packed struct(u8) {
    __: u4 = 0,
    palette: u1 = 0,
    flip_x: bool = false,
    flip_y: bool = false,
    below_bg: bool = false,
};

const Sprite = struct {
    x: u8 = 0,
    y: u8 = 0,
    name: u8 = 0,
    attr: SpriteAttributes = .{},
};

pub const State = struct {
    const Self = @This();

    selected_count: u8 = 0,
    read_index: u8 = 0,
    load_step: u3 = 0,
    fifo_len: u8 = 0,
    tile: Gpu.Tile = .{},
    sprites: [10]Sprite = @splat(.{}),

    pub fn beginLine(self: *Self) void {
        self.read_index = 0;
        self.load_step = 0;
        self.fifo_len = 0;
    }

    pub fn currentSprite(self: *const Self) *const Sprite {
        return &self.sprites[self.read_index - 1];
    }

    pub fn popPixel(self: *Self) ?u2 {
        if (self.fifo_len == 0) {
            return null;
        }

        self.fifo_len -= 1;

        if (self.currentSprite().attr.flip_x) {
            const low: u1 = @truncate(self.tile.chr_low);
            const high: u1 = @truncate(self.tile.chr_high);

            self.tile.chr_low >>= 1;
            self.tile.chr_high >>= 1;

            return (@as(u2, high) << 1) | low;
        }

        self.tile.chr_low = std.math.rotl(u8, self.tile.chr_low, 1);
        self.tile.chr_high = std.math.rotl(u8, self.tile.chr_high, 1);

        const low: u1 = @truncate(self.tile.chr_low);
        const high: u1 = @truncate(self.tile.chr_high);

        return (@as(u2, high) << 1) | low;
    }
};

pub fn selectSprites(gpu: *Gpu) void {
    const height: u8 = if (gpu.ctrl.obj_size) 16 else 8;

    gpu.obj.selected_count = 0;

    var oam_address: u8 = 0;

    while (oam_address < gpu.oam.len) : (oam_address +%= 4) {
        const sprite_y = gpu.oam[oam_address] -% 16;

        if (@as(i32, sprite_y) > gpu.line or
            (@as(i32, sprite_y) + height) <= gpu.line)
        {
            continue;
        }

        if (gpu.obj.selected_count >= max_sprites_per_line) {
            fw.log.trace("Sprite Overflow", .{});
            break;
        }

        const sprite: Sprite = .{
            .y = sprite_y,
            .x = gpu.oam[oam_address +% 1] -% 8,
            .name = gpu.oam[oam_address +% 2],
            .attr = @bitCast(gpu.oam[oam_address +% 3]),
        };

        var insert_index = gpu.obj.selected_count;

        // Prioritise sprites by X position (lower X = higher priority)
        while (insert_index >= 1) : (insert_index -= 1) {
            if (sprite.x >= gpu.obj.sprites[insert_index - 1].x) {
                break;
            }

            gpu.obj.sprites[insert_index] = gpu.obj.sprites[insert_index - 1];
        }

        gpu.obj.sprites[insert_index] = sprite;
        gpu.obj.selected_count += 1;
    }

    if (gpu.obj.selected_count > 0) {
        fw.log.trace("Sprites Selected: {d}", .{gpu.obj.selected_count});
    }
}

pub fn loadTiles(gpu: *Gpu) bool {
    if (gpu.obj.read_index >= gpu.obj.selected_count) {
        return false;
    }

    const sprite = &gpu.obj.sprites[gpu.obj.read_index];

    if (sprite.x > gpu.dot) {
        return false;
    }

    gpu.bg.restartLoad();

    switch (gpu.obj.load_step) {
        0, 2, 4 => gpu.obj.load_step += 1,
        1 => {
            gpu.name_latch = sprite.name;
            gpu.obj.load_step += 1;
        },
        3 => {
            const address = chrAddress(gpu, sprite.y, sprite.attr.flip_y);
            gpu.tile_latch.chr_low = gpu.vram[address];
            gpu.obj.load_step += 1;
        },
        5 => {
            const address = chrAddress(gpu, sprite.y, sprite.attr.flip_y) | 1;
            gpu.tile_latch.chr_high = gpu.vram[address];
            gpu.obj.load_step += 1;
        },
        6 => if (gpu.obj.fifo_len == 0) {
            gpu.obj.tile = gpu.tile_latch;
            gpu.obj.fifo_len = 8;
            gpu.obj.load_step = 0;
            gpu.obj.read_index += 1;
        },
        7 => unreachable,
    }

    return true;
}

fn chrAddress(gpu: *Gpu, sprite_y: u8, flip_y: bool) u13 {
    var fine_y = gpu.line -% sprite_y;
    var name: u13 = gpu.name_latch;

    if (gpu.ctrl.obj_size) {
        name &= 0xfe;

        if (flip_y) {
            fine_y ^= 15;
        }
    } else if (flip_y) {
        fine_y ^= 7;
    }

    return (name << 4) | (@as(u13, fine_y) << 1);
}
