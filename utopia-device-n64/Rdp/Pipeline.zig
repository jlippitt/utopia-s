const std = @import("std");
const sdl3 = @import("sdl3");
const Core = @import("./Core.zig");

pub const Options = struct {
    z_compare_enable: bool = false,
    z_update_enable: bool = false,
};

const Self = @This();

ref_count: u32 = 0,
pipeline: ?sdl3.gpu.GraphicsPipeline = null,

pub fn init() Self {
    return .{};
}

pub fn hasRefs(self: *const Self) bool {
    return self.ref_count != 0;
}

pub fn isActive(self: *const Self) bool {
    return self.pipeline != null;
}

pub fn getBinding(self: *const Self) sdl3.gpu.GraphicsPipeline {
    std.debug.assert(self.hasRefs());
    std.debug.assert(self.isActive());
    return self.pipeline.?;
}

pub fn activate(
    self: *Self,
    gpu: sdl3.gpu.Device,
    vertex_shader: sdl3.gpu.Shader,
    fragment_shader: sdl3.gpu.Shader,
    options: Options,
) error{SdlError}!void {
    std.debug.assert(!self.hasRefs());
    std.debug.assert(!self.isActive());

    self.pipeline = try gpu.createGraphicsPipeline(.{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .vertex_input_state = .{
            .vertex_buffer_descriptions = &.{
                .{
                    .slot = 0,
                    .input_rate = .vertex,
                    .pitch = @sizeOf(Core.Vertex),
                },
            },
            .vertex_attributes = &.{
                .{
                    .buffer_slot = 0,
                    .location = 0,
                    .format = .f32x3,
                    .offset = @offsetOf(Core.Vertex, "pos"),
                },
                .{
                    .buffer_slot = 0,
                    .location = 1,
                    .format = .f32x4,
                    .offset = @offsetOf(Core.Vertex, "color"),
                },
                .{
                    .buffer_slot = 0,
                    .location = 2,
                    .format = .f32x3,
                    .offset = @offsetOf(Core.Vertex, "tex_coords"),
                },
            },
        },
        .target_info = .{
            .color_target_descriptions = &.{
                .{
                    .format = .r8g8b8a8_unorm,
                    .blend_state = .{
                        .enable_blend = true,
                        .source_color = .src_alpha,
                        .destination_color = .one_minus_src_alpha,
                        .color_blend = .add,
                        .source_alpha = .src_alpha,
                        .destination_alpha = .one_minus_src_alpha,
                        .alpha_blend = .add,
                    },
                },
            },
            .depth_stencil_format = .depth16_unorm,
        },
        .depth_stencil_state = .{
            .compare = .less_or_equal,
            .enable_depth_test = options.z_compare_enable,
            .enable_depth_write = options.z_update_enable,
        },
    });
}

pub fn deactivate(self: *Self, gpu: sdl3.gpu.Device) void {
    std.debug.assert(!self.hasRefs());
    std.debug.assert(self.isActive());
    gpu.releaseGraphicsPipeline(self.pipeline.?);
    self.pipeline = null;
}

pub fn ref(self: *Self) void {
    self.ref_count += 1;
}

pub fn unref(self: *Self) void {
    self.ref_count -= 1;
}
