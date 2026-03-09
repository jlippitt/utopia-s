const builtin = @import("builtin");
const std = @import("std");
const fw = @import("framework");
const sdl3 = @import("sdl3");
const Rdp = @import("../Rdp.zig");
const DisplayList = @import("./DisplayList.zig");
const Pipeline = @import("./Pipeline.zig");
const PipelineCache = @import("./PipelineCache.zig");
const Target = @import("./Target.zig");
const Tmem = @import("./Tmem.zig");
const command = @import("./command.zig");

const max_command_len = 22;
const default_perspective = 1024.0;

pub const InitError = std.mem.Allocator.Error || sdl3.errors.Error;
pub const RenderError = sdl3.errors.Error;

pub const Options = struct {
    perspective_enable: bool = false,
    z_source: ZSource = .per_pixel,
    prim_depth: f32 = 0.0,
    pipeline: Pipeline.Options = .{},
};

const Self = @This();

gpu: sdl3.gpu.Device,
pipeline_cache: PipelineCache,
sampler: sdl3.gpu.Sampler,
target: Target,
tmem: Tmem,
display_list: DisplayList,
word_buf: std.ArrayListUnmanaged(u64),
options: Options = .{},

pub fn init(arena: *std.heap.ArenaAllocator) InitError!Self {
    const format_flags: sdl3.gpu.ShaderFormatFlags = .{ .spirv = true };

    const gpu = try sdl3.gpu.Device.init(format_flags, builtin.mode == .Debug, null);
    errdefer gpu.deinit();

    var pipeline_cache = try PipelineCache.init(arena, gpu, format_flags);
    errdefer pipeline_cache.deinit(gpu);

    const sampler = try gpu.createSampler(.{
        .mag_filter = .linear,
        .min_filter = .nearest,
        .mipmap_mode = .nearest,
        .address_mode_u = .clamp_to_edge,
        .address_mode_v = .clamp_to_edge,
        .address_mode_w = .clamp_to_edge,
    });
    errdefer gpu.releaseSampler(sampler);

    var target = try Target.init(gpu);
    errdefer target.deinit(gpu);

    var tmem = try Tmem.init(arena, gpu);
    errdefer tmem.deinit(gpu);

    const default_pipeline = try pipeline_cache.create(gpu, .{});

    var display_list = try DisplayList.init(arena, gpu, default_pipeline);
    errdefer display_list.deinit(gpu);

    const word_buf = try std.ArrayListUnmanaged(u64).initCapacity(
        arena.allocator(),
        max_command_len,
    );

    return .{
        .gpu = gpu,
        .pipeline_cache = pipeline_cache,
        .sampler = sampler,
        .target = target,
        .tmem = tmem,
        .display_list = display_list,
        .word_buf = word_buf,
    };
}

// External-facing interface

pub fn deinit(self: *Self) void {
    self.display_list.deinit(self.gpu);
    self.tmem.deinit(self.gpu);
    self.target.deinit(self.gpu);
    self.gpu.releaseSampler(self.sampler);
    self.pipeline_cache.deinit(self.gpu);
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
        0x2e => command.setPrimDepth(self, word),
        0x2f => try command.setOtherModes(self, word),
        0x30 => command.loadTlut(self, word),
        0x32 => command.setTileSize(self, word),
        0x33 => command.loadBlock(self, word),
        0x34 => command.loadTile(self, word),
        0x35 => command.setTile(self, word),
        0x36 => try command.drawRectangle(.fill, self) orelse return,
        0x37 => command.setFillColor(self, word),
        0x38 => command.setFogColor(self, word),
        0x39 => command.setBlendColor(self, word),
        0x3a => command.setPrimColor(self, word),
        0x3b => command.setEnvColor(self, word),
        0x3c => command.setCombineMode(self, word),
        0x3d => command.setTextureImage(self, word),
        0x3e => command.setDepthImage(self, word),
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
        .texture = surface.color_texture,
        .load = .load,
        .store = .store,
    };

    const depth_target: sdl3.gpu.DepthStencilTargetInfo = .{
        .texture = surface.depth_texture,
        .clear_depth = 1.0,
        .load = .load,
        .store = .store,
        .clear_stencil = 0.0,
        .stencil_load = .do_not_care,
        .stencil_store = .do_not_care,
        .cycle = false,
    };

    const vertex_state: VertexState = .{
        .dimensions = .{
            @floatFromInt(surface.image_width),
            @floatFromInt(surface.image_height),
        },
    };

    const command_buffer = try self.gpu.acquireCommandBuffer();

    {
        const render_pass = command_buffer.beginRenderPass(&.{color_target}, depth_target);
        defer render_pass.end();

        command_buffer.pushVertexUniformData(0, std.mem.asBytes(&vertex_state));

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
            render_pass.bindGraphicsPipeline(display_group.pipeline.getBinding());

            render_pass.setScissor(display_group.scissor);

            command_buffer.pushFragmentUniformData(
                0,
                std.mem.asBytes(&display_group.tex[0].desc.transform()),
            );

            command_buffer.pushFragmentUniformData(
                1,
                std.mem.asBytes(&display_group.tex[1].desc.transform()),
            );

            command_buffer.pushFragmentUniformData(
                2,
                std.mem.asBytes(&display_group.frag_state),
            );

            render_pass.bindFragmentSamplers(0, &.{
                .{
                    .texture = display_group.tex[0].texture.getBinding(),
                    .sampler = self.sampler,
                },
            });

            render_pass.bindFragmentSamplers(1, &.{
                .{
                    .texture = display_group.tex[1].texture.getBinding(),
                    .sampler = self.sampler,
                },
            });

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

pub fn getRdpConst(self: *const Self) *const Rdp {
    return @alignCast(@fieldParentPtr("core", self));
}

pub fn getRdram(self: *Self) []u8 {
    return self.getRdp().getDevice().rdram;
}

pub fn getRdramConst(self: *const Self) []const u8 {
    return self.getRdpConst().getDeviceConst().rdram;
}

pub const Vertex = extern struct {
    pos: [3]f32 = .{ 0.0, 0.0, -1.0 },
    color: [4]f32 = @splat(0.0),
    tex_coords: [3]f32 = .{ 0.0, 0.0, default_perspective },
};

pub const Index = u16;

pub const PixelSize = enum(u2) {
    @"4",
    @"8",
    @"16",
    @"32",
};

pub const PixelFormat = enum(u3) {
    rgba,
    yuv,
    color_index,
    ia,
    i,
    _,
};

pub const ZSource = enum(u1) {
    per_pixel,
    prim_depth,
};

const VertexState = extern struct {
    dimensions: [2]f32,
};
