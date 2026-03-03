const std = @import("std");
const fw = @import("framework");
const Core = @import("../Core.zig");
const DisplayList = @import("../DisplayList.zig");

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

    const cmd: Rectangle = @bitCast(args[0]);
    fw.log.debug("RECTANGLE: {any}", .{cmd});

    var vertices: [4]Core.Vertex = undefined;

    const xl: u32, const yl: u32 = switch (core.display_list.getCycleType()) {
        .copy, .fill => .{
            @as(u32, cmd.xl + 1),
            @as(u32, cmd.yl + 1),
        },
        else => .{
            cmd.xl,
            cmd.yl,
        },
    };

    const left = @as(f32, @floatFromInt(cmd.xh)) / 4.0;
    const top = @as(f32, @floatFromInt(cmd.yh)) / 4.0;
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
    yh: u12,
    xh: u12,
    __0: u8,
    yl: u12,
    xl: u12,
    __1: u8,
};
