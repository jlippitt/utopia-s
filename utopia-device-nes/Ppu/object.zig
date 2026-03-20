const std = @import("std");
const fw = @import("framework");
const Ppu = @import("../Ppu.zig");
const background = @import("./background.zig");

const max_sprites_per_line = 8;

pub const SpriteAttributes = packed struct(u8) {
    palette: u2 = 0,
    __: u3 = 0,
    below_bg: bool = false,
    flip_x: bool = false,
    flip_y: bool = false,
};

pub const Sprite = struct {
    x: i32 = 0,
    attr: SpriteAttributes = .{},
    chr_low: u8 = 0,
    chr_high: u8 = 0,
};

pub const State = struct {
    selected_count: u8 = 0,
    sprite_zero_selected: bool = false,
    sprite_y: u8 = 0,
    sprite_name: u8 = 0,
    secondary_oam: [32]u8 = @splat(0xff),
    sprites: [8]Sprite = @splat(.{}),
};

pub fn selectSprites(ppu: *Ppu) void {
    @memset(&ppu.obj.secondary_oam, 0xff);

    const height: i32 = if (ppu.ctrl.obj_size) 16 else 8;

    ppu.obj.selected_count = 0;
    ppu.obj.sprite_zero_selected = false;

    // For specifics on M and N indexes (and details on sprite overflow bug), see NESDev Wiki
    var n: u8 = 0;
    var m: u2 = 0;

    while (true) {
        const read_index = n | m;
        const sprite_y = ppu.oam.get(read_index);

        const is_on_line = @as(i32, sprite_y) <= ppu.line and
            (@as(i32, sprite_y) + height) > ppu.line;

        if (ppu.obj.selected_count < max_sprites_per_line) {
            const write_index = ppu.obj.selected_count << 2;
            ppu.obj.secondary_oam[write_index] = sprite_y;

            if (is_on_line) {
                ppu.obj.secondary_oam[write_index +% 1] = ppu.oam.get(read_index +% 1);
                ppu.obj.secondary_oam[write_index +% 2] = ppu.oam.get(read_index +% 2);
                ppu.obj.secondary_oam[write_index +% 3] = ppu.oam.get(read_index +% 3);
                ppu.obj.selected_count += 1;

                if (n == 0) {
                    ppu.obj.sprite_zero_selected = true;
                }
            }
        } else if (is_on_line) {
            ppu.status.sprite_overflow = true;
            fw.log.trace("Sprite Overflow: {}", .{ppu.status.sprite_overflow});
        } else {
            // Sprite overflow bug
            m +%= 1;
        }

        n +%= 4;

        if (n == 0) {
            break;
        }
    }

    if (ppu.obj.selected_count > 0) {
        fw.log.trace("Sprites Selected: {d}", .{ppu.obj.selected_count});
        fw.log.trace("Sprite Zero Selected: {}", .{ppu.obj.sprite_zero_selected});
    }
}

pub fn loadTiles(ppu: *Ppu) void {
    const cartridge = &ppu.getDevice().cartridge;
    const sprite_index: u3 = @truncate(ppu.dot >> 3);
    const oam_index: u5 = @as(u5, sprite_index) << 2;
    const sprite = &ppu.obj.sprites[sprite_index];

    switch (@as(u3, @truncate(ppu.dot))) {
        0 => {
            cartridge.setVramAddress(background.nameAddress(ppu));
            ppu.obj.sprite_y = ppu.obj.secondary_oam[oam_index];
        },
        1 => {
            _ = cartridge.readVram();
            ppu.obj.sprite_name = ppu.obj.secondary_oam[oam_index + 1];
        },
        2 => {
            cartridge.setVramAddress(background.attrAddress(ppu));
            sprite.attr = @bitCast(ppu.obj.secondary_oam[oam_index + 2]);
        },
        3 => {
            _ = cartridge.readVram();
            sprite.x = @as(i32, ppu.obj.secondary_oam[oam_index + 3]) + 8;
        },
        4 => {
            cartridge.setVramAddress(chrAddress(ppu, sprite.attr.flip_y));
            sprite.x = @as(i32, ppu.obj.secondary_oam[oam_index + 3]) + 8;
        },
        5 => {
            sprite.chr_low = cartridge.readVram();
            sprite.x = @as(i32, ppu.obj.secondary_oam[oam_index + 3]) + 8;
        },
        6 => {
            cartridge.setVramAddress(chrAddress(ppu, sprite.attr.flip_y) | 8);
            sprite.x = @as(i32, ppu.obj.secondary_oam[oam_index + 3]) + 8;
        },
        7 => {
            sprite.chr_high = cartridge.readVram();
            sprite.x = @as(i32, ppu.obj.secondary_oam[oam_index + 3]) + 8;
        },
    }
}

pub fn render(ppu: *Ppu, bg_color: u5) u5 {
    const start_x: i32 = if (!ppu.mask.bg_enable)
        std.math.maxInt(i32)
    else if (!ppu.mask.bg_show_left)
        8
    else
        0;

    var color_index = bg_color;
    var sprite_blocked = false;

    for (ppu.obj.sprites[0..ppu.obj.selected_count], 0..) |*sprite, index| {
        sprite.x -= 1;

        if (sprite.x < 0 or sprite.x >= 8 or ppu.dot < start_x) {
            continue;
        }

        const flip_mask: u3 = if (sprite.attr.flip_x) 7 else 0;
        const shift = fw.num.truncate(u3, sprite.x) ^ flip_mask;
        const low: u1 = @truncate(sprite.chr_low >> shift);
        const high: u1 = @truncate(sprite.chr_high >> shift);
        const pixel_value = (@as(u2, high) << 1) | low;

        if (pixel_value == 0) {
            continue;
        }

        if (index == 0 and ppu.obj.sprite_zero_selected and bg_color != 0 and ppu.dot != 255) {
            ppu.status.sprite_zero_hit = true;
            fw.log.debug("Sprite Zero Hit: {}", .{ppu.status.sprite_zero_hit});
        }

        if (sprite_blocked or (sprite.attr.below_bg and bg_color != 0)) {
            continue;
        }

        color_index = 0x10 | (@as(u5, sprite.attr.palette) << 2) | pixel_value;

        // Prevent any more sprites from being drawn on top of this one
        sprite_blocked = true;
    }

    return color_index;
}

fn chrAddress(ppu: *Ppu, flip_y: bool) u15 {
    var row = fw.num.truncate(u15, ppu.line - ppu.obj.sprite_y);

    if (ppu.ctrl.obj_size) {
        row &= 15;

        if (flip_y) {
            row ^= 15;
        }

        return (@as(u15, ppu.obj.sprite_name & 0x01) << 12) |
            (@as(u15, ppu.obj.sprite_name & 0xfe) << 4) |
            ((row & 8) << 1) | (row & 7);
    }

    row &= 7;

    if (flip_y) {
        row ^= 7;
    }

    return (@as(u15, ppu.ctrl.obj_chr_table) << 12) |
        (@as(u15, ppu.obj.sprite_name) << 4) |
        row;
}
