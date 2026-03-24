const fw = @import("framework");
const Gpu = @import("../Gpu.zig");

const max_sprites_per_line = 10;

const SpriteAttributes = packed struct(u8) {
    __: u4 = 0,
    palette: bool = false,
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
    selected_count: u8 = 0,
    sprites: [10]Sprite = @splat(.{}),
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
