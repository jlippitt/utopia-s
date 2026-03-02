const std = @import("std");
const fw = @import("framework");
const Core = @import("../Core.zig");
const DisplayList = @import("../DisplayList.zig");
const command = @import("../command.zig");

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
        try core.target.update(core.gpu);
    }

    const cmd: Rectangle = @bitCast(args[0]);
    fw.log.debug("RECTANGLE: {any}", .{cmd});

    var vertices: [4]Core.Vertex = undefined;

    const left = cmd.xh.float();
    const right = cmd.xl.float() + 1.0;
    const top = cmd.yh.float();
    const bottom = cmd.yl.float() + 1.0;

    vertices[0].pos[0] = left;
    vertices[0].pos[1] = top;
    vertices[1].pos[0] = left;
    vertices[1].pos[1] = bottom;
    vertices[2].pos[0] = right;
    vertices[2].pos[1] = top;
    vertices[3].pos[0] = right;
    vertices[3].pos[1] = bottom;

    for (&vertices) |*vertex| {
        // TODO: Z-buffering
        vertex.pos[2] = 0.0;

        // TODO: Proper fill color implementation
        vertex.color = core.fill_color;
    }

    fw.log.debug("Vertices: {any}", .{vertices});

    if (!core.display_list.hasCapacity(DisplayList.rectangle_size)) {
        try core.render();
    }

    core.display_list.pushRectangle(&vertices);
}

const Rectangle = packed struct(u64) {
    yh: command.Fixed(u12, 2),
    xh: command.Fixed(u12, 2),
    __0: u8,
    yl: command.Fixed(u12, 2),
    xl: command.Fixed(u12, 2),
    __1: u8,
};
