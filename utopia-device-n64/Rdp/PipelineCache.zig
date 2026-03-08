const std = @import("std");
const sdl3 = @import("sdl3");
const fw = @import("framework");
const Pipeline = @import("./Pipeline.zig");

const vertex_src align(@alignOf(u32)) = @embedFile("rdp.vert").*;
const fragment_src align(@alignOf(u32)) = @embedFile("rdp.frag").*;

const pool_size = 32;

const Self = @This();

vertex_shader: sdl3.gpu.Shader,
fragment_shader: sdl3.gpu.Shader,
lru: fw.lru.Lru(Pipeline),

pub fn init(
    arena: *std.heap.ArenaAllocator,
    gpu: sdl3.gpu.Device,
    format_flags: sdl3.gpu.ShaderFormatFlags,
) error{ OutOfMemory, SdlError }!Self {
    const vertex_shader = try gpu.createShader(.{
        .code = &vertex_src,
        .entry_point = "main",
        .format = format_flags,
        .stage = .vertex,
    });
    errdefer gpu.releaseShader(vertex_shader);

    const fragment_shader = try gpu.createShader(.{
        .code = &fragment_src,
        .entry_point = "main",
        .format = format_flags,
        .stage = .fragment,
        .num_samplers = 1,
        .num_uniform_buffers = 2,
    });
    errdefer gpu.releaseShader(fragment_shader);

    return .{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .lru = try .init(
            arena.allocator(),
            pool_size,
            .init(),
        ),
    };
}

pub fn deinit(self: *Self, gpu: sdl3.gpu.Device) void {
    var iter = self.lru.iterator();

    while (iter.next()) |pipeline| {
        pipeline.deactivate(gpu);
    }

    gpu.releaseShader(self.fragment_shader);
    gpu.releaseShader(self.vertex_shader);
}

pub fn create(
    self: *Self,
    gpu: sdl3.gpu.Device,
    options: Pipeline.Options,
) error{SdlError}!*Pipeline {
    var hasher = std.hash.Wyhash.init(0);
    std.hash.autoHash(&hasher, options);
    const key = hasher.final();

    const result = self.lru.getOrPut(key);
    const pipeline = result.value_ptr;

    if (result.found_existing) {
        return pipeline;
    }

    if (pipeline.hasRefs()) {
        fw.log.panic("Pipeline cache full", .{});
    }

    if (pipeline.isActive()) {
        pipeline.deactivate(gpu);
    }

    try pipeline.activate(gpu, self.vertex_shader, self.fragment_shader, options);

    return pipeline;
}
