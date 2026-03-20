const fw = @import("framework");
const Ppu = @import("../Ppu.zig");

const max_sprites_per_line = 8;

pub const State = struct {
    selected_count: u8 = 0,
    secondary_oam: [32]u8 = @splat(0xff),
};

pub fn selectSprites(ppu: *Ppu) void {
    @memset(&ppu.obj.secondary_oam, 0xff);

    const height: i32 = if (ppu.ctrl.obj_size) 16 else 8;

    ppu.obj.selected_count = 0;

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
    }
}
