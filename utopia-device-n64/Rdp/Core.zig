const builtin = @import("builtin");
const std = @import("std");
const fw = @import("framework");
const sdl3 = @import("sdl3");
const Rdp = @import("../Rdp.zig");
const DisplayList = @import("./DisplayList.zig");
const Target = @import("./Target.zig");
const command = @import("./command.zig");

const vertex_src align(@alignOf(u32)) = @embedFile("rdp.vert").*;
const fragment_src align(@alignOf(u32)) = @embedFile("rdp.frag").*;

const max_command_len = 22;

pub const InitError = std.mem.Allocator.Error || sdl3.errors.Error;
pub const RenderError = sdl3.errors.Error;

const Self = @This();

gpu: sdl3.gpu.Device,
pipeline: sdl3.gpu.GraphicsPipeline,
target: Target,
display_list: DisplayList,
word_buf: std.ArrayListUnmanaged(u64),
fill_color: [4]f32 = @splat(0.0),

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
        .num_uniform_buffers = 1,
    });
    defer gpu.releaseShader(fragment_shader);

    const pipeline = try gpu.createGraphicsPipeline(.{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .vertex_input_state = .{
            .vertex_buffer_descriptions = &.{
                .{
                    .slot = 0,
                    .input_rate = .vertex,
                    .pitch = @sizeOf(Vertex),
                },
            },
            .vertex_attributes = &.{
                .{
                    .buffer_slot = 0,
                    .location = 0,
                    .format = .f32x3,
                    .offset = @offsetOf(Vertex, "pos"),
                },
                .{
                    .buffer_slot = 0,
                    .location = 1,
                    .format = .f32x4,
                    .offset = @offsetOf(Vertex, "color"),
                },
            },
        },
        .target_info = .{
            .color_target_descriptions = &.{
                .{
                    .format = .r8g8b8a8_unorm,
                },
            },
        },
    });
    errdefer gpu.releaseGraphicsPipeline(pipeline);

    var target = try Target.init(gpu);
    errdefer target.deinit(gpu);

    var display_list = try DisplayList.init(arena, gpu);
    errdefer display_list.deinit(gpu);

    const word_buf = try std.ArrayListUnmanaged(u64).initCapacity(
        arena.allocator(),
        max_command_len,
    );

    return .{
        .gpu = gpu,
        .pipeline = pipeline,
        .target = target,
        .display_list = display_list,
        .word_buf = word_buf,
    };
}

// External-facing interface

pub fn deinit(self: *Self) void {
    self.display_list.deinit(self.gpu);
    self.target.deinit(self.gpu);
    self.gpu.releaseGraphicsPipeline(self.pipeline);
    self.gpu.deinit();
}

pub fn downloadImageData(self: *Self) RenderError!void {
    try self.render();
    try self.target.downloadImageData(self.gpu, self.getRdram());
}

pub fn step(self: *Self, word: u64) RenderError!void {
    self.word_buf.appendAssumeCapacity(word);

    switch (@as(u6, @truncate(self.word_buf.items[0] >> 56))) {
        0x08 => try command.drawTriangle(.{}, self) orelse return,
        0x09 => try command.drawTriangle(.{
            .z_buffer = true,
        }, self) orelse return,
        0x0a => try command.drawTriangle(.{
            .texture = true,
        }, self) orelse return,
        0x0b => try command.drawTriangle(.{
            .texture = true,
            .z_buffer = true,
        }, self) orelse return,
        0x0c => try command.drawTriangle(.{
            .shade = true,
        }, self) orelse return,
        0x0d => try command.drawTriangle(.{
            .shade = true,
            .z_buffer = true,
        }, self) orelse return,
        0x0e => try command.drawTriangle(.{
            .shade = true,
            .texture = true,
        }, self) orelse return,
        0x0f => try command.drawTriangle(.{
            .shade = true,
            .texture = true,
            .z_buffer = true,
        }, self) orelse return,
        0x24 => try command.drawRectangle(.texture, self) orelse return,
        0x25 => try command.drawRectangle(.texture_flip, self) orelse return,
        0x26 => command.syncLoad(self),
        0x27 => command.syncPipe(self),
        0x28 => command.syncTile(self),
        0x29 => try command.syncFull(self),
        0x2d => command.setScissor(self, word),
        0x2f => command.setOtherModes(self, word),
        0x36 => try command.drawRectangle(.fill, self) orelse return,
        0x37 => command.setFillColor(self, word),
        0x38 => command.setFogColor(self, word),
        0x39 => command.setBlendColor(self, word),
        0x3a => command.setPrimColor(self, word),
        0x3b => command.setEnvColor(self, word),
        0x3c => command.setCombineMode(self, word),
        0x3f => command.setColorImage(self, word),
        else => |cmd| fw.log.debug("Unknown Command: {X:02}", .{cmd}),
    }

    self.word_buf.clearRetainingCapacity();
}

// Internal-facing interface

pub fn render(self: *Self) RenderError!void {
    if (self.display_list.isEmpty()) {
        return;
    }

    try self.display_list.uploadBuffers(self.gpu);

    const surface = self.target.getSurface() orelse {
        return;
    };

    const color_target: sdl3.gpu.ColorTargetInfo = .{
        .texture = surface.color_image_texture,
        .load = .clear,
        .store = .store,
        .clear_color = .{
            .r = 0.0,
            .g = 0.0,
            .b = 0.0,
            .a = 0.0,
        },
    };

    const command_buffer = try self.gpu.acquireCommandBuffer();

    {
        const render_pass = command_buffer.beginRenderPass(&.{color_target}, null);
        defer render_pass.end();

        render_pass.bindGraphicsPipeline(self.pipeline);

        render_pass.bindIndexBuffer(.{
            .buffer = self.display_list.getIndexBuffer(),
            .offset = 0,
        }, .indices_16bit);

        render_pass.bindVertexBuffers(0, &.{.{
            .buffer = self.display_list.getVertexBuffer(),
            .offset = 0,
        }});

        const display_groups = self.display_list.getDisplayGroups();

        fw.log.debug("Display Groups: {any}", .{display_groups});

        var index_offset: u32 = 0;

        for (display_groups) |display_group| {
            command_buffer.pushFragmentUniformData(0, std.mem.asBytes(&display_group.frag_state));
            render_pass.drawIndexedPrimitives(display_group.len, 1, index_offset, 0, 0);
            index_offset += display_group.len;
        }
    }

    try command_buffer.submit();

    self.display_list.clear();
}

pub fn getRdp(self: *Self) *Rdp {
    return @alignCast(@fieldParentPtr("core", self));
}

pub fn getRdram(self: *Self) []u8 {
    return self.getRdp().getDevice().rdram;
}

pub const Vertex = extern struct {
    pos: [3]f32,
    color: [4]f32,
};

pub const Index = u16;
