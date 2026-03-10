const std = @import("std");
const fw = @import("framework");
const Core = @import("../Core.zig");
const DisplayList = @import("../DisplayList.zig");
const Tmem = @import("../Tmem.zig");

pub const RectangleType = enum {
    fill,
    texture,
    texture_flip,
};

pub fn drawRectangle(comptime rect_type: RectangleType, core: *Core) !?void {
    const word_count = comptime 1 + if (rect_type == .fill) 0 else 1;
    const args = core.word_buf.items;

    if (args.len < word_count) {
        return null;
    }

    if (core.target.paramsChanged()) {
        try core.render();
        try core.target.update(core.gpu, core.getRdram());
    }

    core.target.markDirty(core.options.pipeline.z_update_enable);

    const cmd: Rectangle = @bitCast(args[0]);
    fw.log.debug("RECTANGLE: {any}", .{cmd});

    const cycle_type = core.display_list.getCycleType();

    var vertices: [4]Core.Vertex = @splat(.{});

    const xh: u32 = cmd.xh;
    const yh: u32 = cmd.yh;
    var xl: u32 = cmd.xl;
    var yl: u32 = cmd.yl;

    if (cycle_type == .copy or cycle_type == .fill) {
        xl += 4;
        yl += 4;
    }

    const left = @as(f32, @floatFromInt(xh)) / 4.0;
    const top = @as(f32, @floatFromInt(yh)) / 4.0;
    const right = @as(f32, @floatFromInt(xl)) / 4.0;
    const bottom = @as(f32, @floatFromInt(yl)) / 4.0;

    vertices[0].pos[0] = left;
    vertices[0].pos[1] = top;
    vertices[1].pos[0] = left;
    vertices[1].pos[1] = bottom;
    vertices[2].pos[0] = right;
    vertices[2].pos[1] = top;
    vertices[3].pos[0] = right;
    vertices[3].pos[1] = bottom;

    var texture: [2]Tmem.TextureDescriptor = core.tmem.nullTexture();

    if (comptime rect_type != .fill) {
        const tile = core.tmem.getTile(cmd.tile);

        const tex_coords: TexCoords = @bitCast(args[1]);
        fw.log.debug("Tex Coords: {any}", .{tex_coords});

        const s = @as(i64, tex_coords.s) << 7;
        const t = @as(i64, tex_coords.t) << 7;
        var dsdx: i64 = tex_coords.dsdx << 2;
        const dtdy: i64 = tex_coords.dtdy << 2;

        if (cycle_type == .copy) {
            dsdx = @divTrunc(dsdx, 4);
        }

        const tile_x = @as(i64, tile.x()) << 12;
        const tile_y = @as(i64, tile.y()) << 12;

        const sh = s - tile_x;
        const th = t - tile_y;
        const sl = sh + ((dsdx * (@as(i64, xl) - xh)) >> 2);
        const tl = th + ((dtdy * (@as(i64, yl) - yh)) >> 2);

        const offset: f32 = if (core.display_list.getSampleType() == .linear) 0.5 else 0;

        const tex_left = @as(f32, @floatFromInt(sh)) / 4096.0 + offset;
        const tex_right = @as(f32, @floatFromInt(sl)) / 4096.0 + offset;
        const tex_top = @as(f32, @floatFromInt(th)) / 4096.0 + offset;
        const tex_bottom = @as(f32, @floatFromInt(tl)) / 4096.0 + offset;

        vertices[0].tex_coords[0] = tex_left;
        vertices[0].tex_coords[1] = tex_top;
        vertices[3].tex_coords[0] = tex_right;
        vertices[3].tex_coords[1] = tex_bottom;

        if (comptime rect_type == .texture_flip) {
            vertices[1].tex_coords[0] = tex_right;
            vertices[1].tex_coords[1] = tex_top;
            vertices[2].tex_coords[0] = tex_left;
            vertices[2].tex_coords[1] = tex_bottom;
        } else {
            vertices[1].tex_coords[0] = tex_left;
            vertices[1].tex_coords[1] = tex_bottom;
            vertices[2].tex_coords[0] = tex_right;
            vertices[2].tex_coords[1] = tex_top;
        }

        texture = try core.tmem.createTexture(core.gpu, cmd.tile);
    }

    if (core.options.z_source == .prim_depth) {
        const bias = if (core.options.z_mode == .decal) Core.decal_bias else 0.0;

        for (&vertices) |*vertex| {
            vertex.pos[2] = core.options.prim_depth + bias;
        }
    }

    fw.log.debug("Vertices: {any}", .{vertices});

    if (!core.display_list.hasCapacity(DisplayList.rectangle_size)) {
        try core.render();
    }

    core.display_list.pushRectangle(texture, &vertices);
}

const Rectangle = packed struct(u64) {
    yh: u12,
    xh: u12,
    tile: u3,
    __0: u5,
    yl: u12,
    xl: u12,
    __1: u8,
};

const TexCoords = packed struct(u64) {
    dtdy: u16,
    dsdx: u16,
    t: u16,
    s: u16,
};
