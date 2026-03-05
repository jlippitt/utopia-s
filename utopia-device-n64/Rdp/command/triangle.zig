const std = @import("std");
const fw = @import("framework");
const Core = @import("../Core.zig");
const DisplayList = @import("../DisplayList.zig");

pub const TriangleAttributes = struct {
    z_buffer: bool = false,
    texture: bool = false,
    shade: bool = false,
};

pub fn drawTriangle(comptime attr: TriangleAttributes, core: *Core) !?void {
    const word_count = comptime 4 +
        (if (attr.shade) 8 else 0) +
        (if (attr.texture) 8 else 0) +
        (if (attr.z_buffer) 2 else 0);

    const args = core.word_buf.items;

    if (args.len < word_count) {
        return null;
    }

    if (core.target.paramsChanged()) {
        try core.render();
        try core.target.update(core.gpu, core.getRdram());
    }

    core.target.markDirty();

    const cmd: Triangle = @bitCast(args[0]);
    fw.log.debug("TRIANGLE: {any}", .{cmd});

    var vertices: [3]Core.Vertex = @splat(.{});

    const edge_l: Edge = @bitCast(args[1]);
    fw.log.debug("Edge L: {any}", .{edge_l});
    const edge_h: Edge = @bitCast(args[2]);
    fw.log.debug("Edge H: {any}", .{edge_h});
    const edge_m: Edge = @bitCast(args[3]);
    fw.log.debug("Edge M: {any}", .{edge_m});

    const yh = @as(i64, cmd.yh) << 14;
    const ym = @as(i64, cmd.ym) << 14;
    const yl = @as(i64, cmd.yl) << 14;
    const xh: i64 = edge_h.x;
    const xl: i64 = edge_l.x;
    const dxhdy: i64 = edge_h.dxdy;

    const yh_floor = yh & ~@as(i64, 0xffff);

    const high_y = yh - yh_floor;
    const mid_y = ym - yh_floor;
    const low_y = yl - yh_floor;
    const mid_x = xl - (xh + ((mid_y * dxhdy) >> 16));

    vertices[0].pos[0] = float(xh + ((high_y * dxhdy) >> 16));
    vertices[0].pos[1] = float(yh);
    vertices[1].pos[0] = float(xl);
    vertices[1].pos[1] = float(ym);
    vertices[2].pos[0] = float(xh + ((low_y * dxhdy) >> 16));
    vertices[2].pos[1] = float(yl);

    const arg_index = 4;

    if (comptime attr.shade) {
        const shade: Shade = @bitCast(args[arg_index + 0]);
        fw.log.debug("Shade: {any}", .{shade});
        const shade_dx: Shade = @bitCast(args[arg_index + 1]);
        fw.log.debug("Shade DX: {any}", .{shade_dx});
        const shade_frac: ShadeFrac = @bitCast(args[arg_index + 2]);
        fw.log.debug("Shade Frac: {any}", .{shade_frac});
        const shade_dx_frac: ShadeFrac = @bitCast(args[arg_index + 3]);
        fw.log.debug("Shade DX Frac: {any}", .{shade_dx_frac});
        const shade_de: Shade = @bitCast(args[arg_index + 4]);
        fw.log.debug("Shade DE: {any}", .{shade_de});
        const shade_dy: Shade = @bitCast(args[arg_index + 5]);
        fw.log.debug("Shade DY: {any}", .{shade_dy});
        const shade_de_frac: ShadeFrac = @bitCast(args[arg_index + 6]);
        fw.log.debug("Shade DE Frac: {any}", .{shade_de_frac});
        const shade_dy_frac: ShadeFrac = @bitCast(args[arg_index + 7]);
        fw.log.debug("Shade DY Frac: {any}", .{shade_dy_frac});

        const color = parseColor(shade, shade_frac);
        fw.log.debug("Color: {any}", .{color});
        const color_dx = parseColor(shade_dx, shade_dx_frac);
        fw.log.debug("Color DX: {any}", .{color_dx});
        const color_de = parseColor(shade_de, shade_de_frac);
        fw.log.debug("Color DE: {any}", .{color_de});
        const color_dy = parseColor(shade_dy, shade_dy_frac);
        fw.log.debug("Color DY: {any}", .{color_dy});

        for (0..4) |el| {
            vertices[0].color[el] = float(color[el] +
                ((high_y * color_de[el]) >> 16)) / 256.0;
            vertices[1].color[el] = float(color[el] +
                ((mid_y * color_de[el]) >> 16) +
                ((mid_x * color_dx[el]) >> 16)) / 256.0;
            vertices[2].color[el] = float(color[el] +
                ((low_y * color_de[el]) >> 16)) / 256.0;
        }
    }

    fw.log.debug("Vertices: {any}", .{vertices});

    if (!core.display_list.hasCapacity(DisplayList.triangle_size)) {
        try core.render();
    }

    core.display_list.pushTriangle(core.gpu, &core.tmem, null, &vertices);
}

fn parseColor(int: Shade, frac: ShadeFrac) [4]i64 {
    return .{
        parseIntensity(int.r, frac.r),
        parseIntensity(int.g, frac.g),
        parseIntensity(int.b, frac.b),
        parseIntensity(int.a, frac.a),
    };
}

fn parseIntensity(int: i16, frac: u16) i64 {
    return (@as(i64, int) << 16) | fw.num.zeroExtend(i64, frac);
}

pub fn float(value: i64) f32 {
    return @as(f32, @floatFromInt(value)) / 65536.0;
}

const Triangle = packed struct(u64) {
    yh: i14,
    __0: u2,
    ym: i14,
    __1: u2,
    yl: i14,
    __2: u2,
    tile: u3,
    level: u3,
    __3: u1,
    right: bool,
    __: u8,
};

const Edge = packed struct(u64) {
    dxdy: i30,
    __0: u2,
    x: i28,
    __1: u4,
};

const Shade = packed struct(u64) {
    a: i16,
    b: i16,
    g: i16,
    r: i16,
};

const ShadeFrac = packed struct(u64) {
    a: u16,
    b: u16,
    g: u16,
    r: u16,
};
