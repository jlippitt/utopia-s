const std = @import("std");
const fw = @import("framework");
const Core = @import("../Core.zig");
const DisplayList = @import("../DisplayList.zig");
const command = @import("../command.zig");

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
        try core.target.update(core.gpu);
    }

    const cmd: Triangle = @bitCast(args[0]);
    fw.log.debug("TRIANGLE: {any}", .{cmd});

    var vertices: [3]Core.Vertex = undefined;

    const edge_l: Edge = @bitCast(args[1]);
    fw.log.debug("Edge L: {any}", .{edge_l});
    const edge_h: Edge = @bitCast(args[2]);
    fw.log.debug("Edge H: {any}", .{edge_h});
    const edge_m: Edge = @bitCast(args[3]);
    fw.log.debug("Edge M: {any}", .{edge_m});

    const yh = cmd.yh.float();
    const ym = cmd.ym.float();
    const yl = cmd.yl.float();
    const xh = edge_h.x.float();
    const xl = edge_l.x.float();
    const dxhdy = edge_h.dxdy.float();

    const high_y = yh - @floor(yh);
    const low_y = yl - @floor(yh);

    vertices[0].pos[0] = xh + high_y * dxhdy;
    vertices[0].pos[1] = yh;
    vertices[1].pos[0] = xl;
    vertices[1].pos[1] = ym;
    vertices[2].pos[0] = xh + low_y * dxhdy;
    vertices[2].pos[1] = yl;

    for (&vertices) |*vertex| {
        // TODO: Z-buffering
        vertex.pos[2] = 0.0;

        // TODO: Proper fill color implementation
        vertex.color = core.fill_color;
    }

    fw.log.debug("Vertices: {any}", .{vertices});

    if (!core.display_list.hasCapacity(DisplayList.triangle_size)) {
        try core.render();
    }

    core.display_list.pushTriangle(&vertices);
}

const Triangle = packed struct(u64) {
    yh: command.Fixed(i14, 2),
    __0: u2,
    ym: command.Fixed(i14, 2),
    __1: u2,
    yl: command.Fixed(i14, 2),
    __2: u2,
    tile: u3,
    level: u3,
    __3: u1,
    right: bool,
    __: u8,
};

const Edge = packed struct(u64) {
    dxdy: command.Fixed(i30, 16),
    __0: u2,
    x: command.Fixed(i28, 16),
    __1: u4,
};
