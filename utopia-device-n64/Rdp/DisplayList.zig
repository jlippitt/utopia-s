const std = @import("std");
const sdl3 = @import("sdl3");
const fw = @import("framework");
const Core = @import("./Core.zig");
const Pipeline = @import("./Pipeline.zig");
const Tmem = @import("./Tmem.zig");
const fragment = @import("./fragment.zig");

const max_display_groups = 256;
const max_buffer_len = 1024;
const index_buffer_size = @sizeOf(Core.Index) * max_buffer_len;
const vertex_buffer_size = @sizeOf(Core.Vertex) * max_buffer_len;

pub const triangle_size = 3;
pub const rectangle_size = 6;

pub const CycleType = enum(u32) {
    one_cycle,
    two_cycle,
    copy,
    fill,
};

const FragmentState = extern struct {
    combine: [2]fragment.CombineMode = @splat(.{}),
    blend: [2]fragment.BlendMode = @splat(.{}),
    fill_colors: [4]fw.color.RgbaUnorm = @splat(.{}),
    fog_color: fw.color.RgbaUnorm = .{},
    blend_color: fw.color.RgbaUnorm = .{},
    prim_color: fw.color.RgbaUnorm = .{},
    env_color: fw.color.RgbaUnorm = .{},
    cycle_type: CycleType = .one_cycle,
    alpha_cvg_select: u32 = 0,
    cvg_times_alpha: u32 = 0,
    color_on_cvg: u32 = 0,
    alpha_compare: u32 = 0,
};

pub const DisplayGroup = struct {
    pipeline: *Pipeline,
    tex: [2]Tmem.TextureDescriptor,
    frag_state: FragmentState,
    len: u32,
};

const Self = @This();

display_groups: std.ArrayList(DisplayGroup),
indices: std.ArrayList(Core.Index),
vertices: std.ArrayList(Core.Vertex),
index_buffer: sdl3.gpu.Buffer,
vertex_buffer: sdl3.gpu.Buffer,
index_upload_buffer: sdl3.gpu.TransferBuffer,
vertex_upload_buffer: sdl3.gpu.TransferBuffer,
frag_state: FragmentState = .{},
frag_state_changed: bool = false,
pipeline: *Pipeline,
pipeline_changed: bool = false,
fill_color: u32 = 0,
pixel_size: Core.PixelSize = .@"32",

pub fn init(
    arena: *std.heap.ArenaAllocator,
    gpu: sdl3.gpu.Device,
    pipeline: *Pipeline,
) error{ OutOfMemory, SdlError }!Self {
    const index_buffer = try gpu.createBuffer(.{
        .size = index_buffer_size,
        .usage = .{ .index = true },
    });
    errdefer gpu.releaseBuffer(index_buffer);

    const vertex_buffer = try gpu.createBuffer(.{
        .size = vertex_buffer_size,
        .usage = .{ .vertex = true },
    });
    errdefer gpu.releaseBuffer(vertex_buffer);

    const index_upload_buffer = try gpu.createTransferBuffer(.{
        .size = index_buffer_size,
        .usage = .upload,
    });
    errdefer gpu.releaseTransferBuffer(index_upload_buffer);

    const vertex_upload_buffer = try gpu.createTransferBuffer(.{
        .size = vertex_buffer_size,
        .usage = .upload,
    });
    errdefer gpu.releaseTransferBuffer(vertex_upload_buffer);

    pipeline.ref();

    return .{
        .display_groups = try .initCapacity(arena.allocator(), max_display_groups),
        .indices = try .initCapacity(arena.allocator(), max_buffer_len),
        .vertices = try .initCapacity(arena.allocator(), max_buffer_len),
        .index_buffer = index_buffer,
        .vertex_buffer = vertex_buffer,
        .index_upload_buffer = index_upload_buffer,
        .vertex_upload_buffer = vertex_upload_buffer,
        .pipeline = pipeline,
    };
}

pub fn deinit(self: *Self, gpu: sdl3.gpu.Device) void {
    self.clear();
    self.pipeline.unref();
    gpu.releaseTransferBuffer(self.vertex_upload_buffer);
    gpu.releaseTransferBuffer(self.index_upload_buffer);
    gpu.releaseBuffer(self.vertex_buffer);
    gpu.releaseBuffer(self.index_buffer);
}

pub fn isEmpty(self: *const Self) bool {
    return self.display_groups.items.len == 0;
}

pub fn getDisplayGroups(self: *const Self) []const DisplayGroup {
    return self.display_groups.items;
}

pub fn getIndexBuffer(self: *const Self) sdl3.gpu.Buffer {
    return self.index_buffer;
}

pub fn getVertexBuffer(self: *const Self) sdl3.gpu.Buffer {
    return self.vertex_buffer;
}

pub fn getCycleType(self: *Self) CycleType {
    return self.frag_state.cycle_type;
}

pub fn clear(self: *Self) void {
    for (self.display_groups.items) |display_group| {
        display_group.pipeline.unref();
        display_group.tex[0].texture.unref();
        display_group.tex[1].texture.unref();
    }

    self.display_groups.clearRetainingCapacity();
    self.indices.clearRetainingCapacity();
    self.vertices.clearRetainingCapacity();
}

pub fn hasCapacity(self: *const Self, len: usize) bool {
    // There will always be fewer vertices than indices, so we can skip
    // checking the vertex array capacity
    return self.display_groups.items.len < max_display_groups and
        (self.indices.items.len + len) <= max_buffer_len;
}

pub fn pushTriangle(
    self: *Self,
    tex: [2]Tmem.TextureDescriptor,
    vertices: *const [3]Core.Vertex,
) void {
    const base_index = self.vertices.items.len;

    self.pushPrimitive(tex, vertices, &.{
        @intCast(base_index),
        @intCast(base_index + 1),
        @intCast(base_index + 2),
    });
}

pub fn pushRectangle(
    self: *Self,
    tex: [2]Tmem.TextureDescriptor,
    vertices: *const [4]Core.Vertex,
) void {
    const base_index = self.vertices.items.len;

    const top_left: Core.Index = @intCast(base_index);
    const bottom_left: Core.Index = @intCast(base_index + 1);
    const top_right: Core.Index = @intCast(base_index + 2);
    const bottom_right: Core.Index = @intCast(base_index + 3);

    self.pushPrimitive(tex, vertices, &.{
        top_left,
        bottom_left,
        top_right,
        top_right,
        bottom_left,
        bottom_right,
    });
}

pub fn setPipeline(self: *Self, pipeline: *Pipeline) void {
    if (pipeline == self.pipeline) {
        return;
    }

    self.pipeline.unref();
    self.pipeline = pipeline;
    self.pipeline.ref();
    self.pipeline_changed = true;
}

pub fn setCombineMode(self: *Self, combine: [2]fragment.CombineMode) void {
    self.frag_state_changed = self.frag_state_changed or
        !std.meta.eql(combine, self.frag_state.combine);

    self.frag_state.combine = combine;
    fw.log.debug("RGB (Cycle 0): {f}", .{combine[0].rgb});
    fw.log.debug("RGB (Cycle 1): {f}", .{combine[1].rgb});
    fw.log.debug("Alpha (Cycle 0): {f}", .{combine[0].a});
    fw.log.debug("Alpha (Cycle 1): {f}", .{combine[1].a});
}

pub fn setBlendMode(self: *Self, blend: [2]fragment.BlendMode) void {
    self.frag_state_changed = self.frag_state_changed or
        !std.meta.eql(blend, self.frag_state.blend);

    self.frag_state.blend = blend;
    fw.log.debug("Blend (Cycle 0): {f}", .{blend[0]});
    fw.log.debug("Blend (Cycle 1): {f}", .{blend[1]});
}

pub fn setFogColor(self: *Self, fog_color: fw.color.RgbaUnorm) void {
    self.frag_state_changed = self.frag_state_changed or
        !std.meta.eql(fog_color, self.frag_state.fog_color);

    self.frag_state.fog_color = fog_color;
    fw.log.debug("Fog Color: {any}", .{fog_color});
}

pub fn setBlendColor(self: *Self, blend_color: fw.color.RgbaUnorm) void {
    self.frag_state_changed = self.frag_state_changed or
        !std.meta.eql(blend_color, self.frag_state.blend_color);

    self.frag_state.blend_color = blend_color;
    fw.log.debug("Blend Color: {any}", .{blend_color});
}

pub fn setPrimColor(self: *Self, prim_color: fw.color.RgbaUnorm) void {
    self.frag_state_changed = self.frag_state_changed or
        !std.meta.eql(prim_color, self.frag_state.prim_color);

    self.frag_state.prim_color = prim_color;
    fw.log.debug("Prim Color: {any}", .{prim_color});
}

pub fn setEnvColor(self: *Self, env_color: fw.color.RgbaUnorm) void {
    self.frag_state_changed = self.frag_state_changed or
        !std.meta.eql(env_color, self.frag_state.env_color);

    self.frag_state.env_color = env_color;
    fw.log.debug("Env Color: {any}", .{env_color});
}

pub fn setCycleType(self: *Self, cycle_type: CycleType) void {
    self.frag_state_changed = self.frag_state_changed or
        cycle_type != self.frag_state.cycle_type;

    self.frag_state.cycle_type = cycle_type;
    fw.log.debug("Cycle Type: {t}", .{cycle_type});
}

pub fn setAlphaCvgSelect(self: *Self, alpha_cvg_select: bool) void {
    self.frag_state_changed = self.frag_state_changed or
        self.frag_state.alpha_cvg_select != @intFromBool(alpha_cvg_select);

    self.frag_state.alpha_cvg_select = @intFromBool(alpha_cvg_select);
    fw.log.debug("AlphaCVGSelect: {}", .{alpha_cvg_select});
}

pub fn setCvgTimesAlpha(self: *Self, cvg_times_alpha: bool) void {
    self.frag_state_changed = self.frag_state_changed or
        self.frag_state.cvg_times_alpha != @intFromBool(cvg_times_alpha);

    self.frag_state.cvg_times_alpha = @intFromBool(cvg_times_alpha);
    fw.log.debug("CVG Times Alpha: {}", .{cvg_times_alpha});
}

pub fn setColorOnCvg(self: *Self, color_on_cvg: bool) void {
    self.frag_state_changed = self.frag_state_changed or
        self.frag_state.color_on_cvg != @intFromBool(color_on_cvg);

    self.frag_state.color_on_cvg = @intFromBool(color_on_cvg);
    fw.log.debug("Color On CVG: {}", .{color_on_cvg});
}

pub fn setAlphaCompare(self: *Self, alpha_compare: bool) void {
    self.frag_state_changed = self.frag_state_changed or
        self.frag_state.alpha_compare != @intFromBool(alpha_compare);

    self.frag_state.alpha_compare = @intFromBool(alpha_compare);
    fw.log.debug("Alpha Compare: {}", .{alpha_compare});
}

pub fn setFillColor(self: *Self, fill_color: u32) void {
    self.fill_color = fill_color;
    self.updateFillColor();
}

pub fn setPixelSize(self: *Self, pixel_size: Core.PixelSize) void {
    self.pixel_size = pixel_size;
    self.updateFillColor();
}

pub fn uploadBuffers(self: *Self, gpu: sdl3.gpu.Device) error{SdlError}!void {
    {
        const indices = try gpu.mapTransferBuffer(self.index_upload_buffer, true);
        defer gpu.unmapTransferBuffer(self.index_upload_buffer);

        @memcpy(
            indices[0..(@sizeOf(Core.Index) * self.indices.items.len)],
            std.mem.sliceAsBytes(self.indices.items),
        );
    }

    {
        const vertices = try gpu.mapTransferBuffer(self.vertex_upload_buffer, true);
        defer gpu.unmapTransferBuffer(self.vertex_upload_buffer);

        @memcpy(
            vertices[0..(@sizeOf(Core.Vertex) * self.vertices.items.len)],
            std.mem.sliceAsBytes(self.vertices.items),
        );
    }

    const command_buffer = try gpu.acquireCommandBuffer();

    {
        const copy_pass = command_buffer.beginCopyPass();
        defer copy_pass.end();

        copy_pass.uploadToBuffer(
            .{
                .transfer_buffer = self.index_upload_buffer,
                .offset = 0,
            },
            .{
                .buffer = self.index_buffer,
                .offset = 0,
                .size = @intCast(@sizeOf(Core.Index) * self.indices.items.len),
            },
            true,
        );

        copy_pass.uploadToBuffer(
            .{
                .transfer_buffer = self.vertex_upload_buffer,
                .offset = 0,
            },
            .{
                .buffer = self.vertex_buffer,
                .offset = 0,
                .size = @intCast(@sizeOf(Core.Vertex) * self.vertices.items.len),
            },
            true,
        );
    }

    try command_buffer.submit();
}

fn pushPrimitive(
    self: *Self,
    tex: [2]Tmem.TextureDescriptor,
    vertices: []const Core.Vertex,
    indices: []const Core.Index,
) void {
    self.indices.appendSliceAssumeCapacity(indices);
    self.vertices.appendSliceAssumeCapacity(vertices);

    if (self.getCurrentDisplayGroup()) |display_group| {
        if (std.meta.eql(tex, display_group.tex) and
            !self.frag_state_changed and
            !self.pipeline_changed)
        {
            display_group.len += @intCast(indices.len);
            return;
        }
    }

    self.pipeline.ref();
    tex[0].texture.ref();
    tex[1].texture.ref();

    self.display_groups.appendAssumeCapacity(.{
        .pipeline = self.pipeline,
        .tex = tex,
        .frag_state = self.frag_state,
        .len = @intCast(indices.len),
    });

    self.frag_state_changed = false;
}

fn getCurrentDisplayGroup(self: *Self) ?*DisplayGroup {
    if (self.display_groups.items.len == 0) {
        return null;
    }

    return &self.display_groups.items[self.display_groups.items.len - 1];
}

fn updateFillColor(self: *Self) void {
    var fill_colors: [4]fw.color.RgbaUnorm = undefined;

    switch (self.pixel_size) {
        .@"4" => fw.log.unimplemented("4BPP fill color", .{}),
        .@"8" => for (&fill_colors, 0..) |*fill_color, index| {
            const shift = @as(u5, @intCast(index ^ 3)) * 8;
            fill_color.* = .fromR8(@truncate(self.fill_color >> shift));
        },
        .@"16" => {
            const colors: [2]fw.color.RgbaUnorm = .{
                .fromRgba16Uint(@truncate(self.fill_color >> 16)),
                .fromRgba16Uint(@truncate(self.fill_color)),
            };

            fill_colors = .{
                colors[0],
                colors[1],
                colors[0],
                colors[1],
            };
        },
        .@"32" => fill_colors = @splat(.fromRgba32Uint(self.fill_color)),
    }

    self.frag_state_changed = self.frag_state_changed or
        !std.meta.eql(self.frag_state.fill_colors, fill_colors);

    self.frag_state.fill_colors = @bitCast(fill_colors);
    fw.log.debug("Fill Colors: {any}", .{self.frag_state.fill_colors});
}
