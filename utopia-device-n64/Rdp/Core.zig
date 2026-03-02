const builtin = @import("builtin");
const std = @import("std");
const fw = @import("framework");
const sdl3 = @import("sdl3");
const Rdp = @import("../Rdp.zig");
const Target = @import("./Target.zig");
const command = @import("./command.zig");

const vertex_src align(@alignOf(u32)) = @embedFile("rdp.vert").*;
const fragment_src align(@alignOf(u32)) = @embedFile("rdp.frag").*;

pub const InitError = std.mem.Allocator.Error || sdl3.errors.Error;
pub const RenderError = sdl3.errors.Error;

const max_command_length = 22;

const Self = @This();

gpu: sdl3.gpu.Device,
pipeline: sdl3.gpu.GraphicsPipeline,
target: Target,
word_buf: std.ArrayListUnmanaged(u64),

pub fn init(arena: *std.heap.ArenaAllocator) InitError!Self {
    const format_flags: sdl3.gpu.ShaderFormatFlags = .{ .spirv = true };

    const gpu = try sdl3.gpu.Device.init(format_flags, builtin.mode == .Debug, null);
    errdefer gpu.deinit();

    const vertex_shader = try gpu.createShader(.{
        .code = &vertex_src,
        .entry_point = "main",
        .format = format_flags,
        .stage = .vertex,
    });
    defer gpu.releaseShader(vertex_shader);

    const fragment_shader = try gpu.createShader(.{
        .code = &fragment_src,
        .entry_point = "main",
        .format = format_flags,
        .stage = .fragment,
    });
    defer gpu.releaseShader(fragment_shader);

    const pipeline = try gpu.createGraphicsPipeline(.{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .vertex_input_state = .{
            // .vertex_buffer_descriptions = &.{
            //     .{
            //         .slot = 0,
            //         .input_rate = .vertex,
            //         .pitch = @sizeOf(Vertex),
            //     },
            // },
            // .vertex_attributes = &.{
            //     .{
            //         .buffer_slot = 0,
            //         .location = 0,
            //         .format = .f32x3,
            //         .offset = @offsetOf(Vertex, "pos"),
            //     },
            //     .{
            //         .buffer_slot = 0,
            //         .location = 1,
            //         .format = .f32x4,
            //         .offset = @offsetOf(Vertex, "color"),
            //     },
            // },
        },
        .target_info = .{
            .color_target_descriptions = &.{
                .{
                    .format = .r8g8b8a8_uint,
                },
            },
        },
    });
    errdefer gpu.releaseGraphicsPipeline(pipeline);

    var target = try Target.init(gpu);
    errdefer target.deinit(gpu);

    const word_buf = try std.ArrayListUnmanaged(u64).initCapacity(
        arena.allocator(),
        max_command_length,
    );

    return .{
        .gpu = gpu,
        .pipeline = pipeline,
        .target = target,
        .word_buf = word_buf,
    };
}

// External-facing interface

pub fn deinit(self: *Self) void {
    self.gpu.releaseGraphicsPipeline(self.pipeline);
    self.target.deinit(self.gpu);
    self.gpu.deinit();
}

pub fn downloadImageData(self: *Self) RenderError!void {
    try self.target.update(self.gpu);
    try self.render();
    try self.target.downloadImageData(self.gpu, self.getRdram());
}

pub fn step(self: *Self, word: u64) RenderError!void {
    self.word_buf.appendAssumeCapacity(word);

    switch (@as(u6, @truncate(self.word_buf.items[0] >> 56))) {
        0x29 => try command.syncFull(self),
        0x2d => command.setScissor(self, word),
        0x3f => command.setColorImage(self, word),
        else => |cmd| fw.log.debug("Unknown Command: {X:02}", .{cmd}),
    }

    _ = self.word_buf.pop();
}

// Internal-facing interface

pub fn render(self: *Self) RenderError!void {
    const surface = self.target.getSurface() orelse {
        return;
    };

    const color_target: sdl3.gpu.ColorTargetInfo = .{
        .texture = surface.color_image_texture,
        .load = .clear,
        .store = .store,
        .clear_color = .{
            .r = 1.0,
            .g = 1.0,
            .b = 1.0,
            .a = 1.0,
        },
    };

    const command_buffer = try self.gpu.acquireCommandBuffer();

    {
        const render_pass = command_buffer.beginRenderPass(&.{color_target}, null);
        defer render_pass.end();

        render_pass.bindGraphicsPipeline(self.pipeline);

        render_pass.drawPrimitives(3, 1, 0, 0);
    }

    try command_buffer.submit();
}

pub fn getRdp(self: *Self) *Rdp {
    return @alignCast(@fieldParentPtr("core", self));
}

pub fn getRdram(self: *Self) []u8 {
    return self.getRdp().getDevice().rdram;
}

pub const Vertex = struct {
    pos: [3]f32,
    color: [4]f32,
};
