const std = @import("std");
const sdl3 = @import("sdl3");
const fw = @import("framework");
const Tmem = @import("../Tmem.zig");
const Texture = @import("./Texture.zig");

const pool_size = 1024;

pub const Id = u32;

const Self = @This();

textures: *[pool_size]Texture,
free_list: *[pool_size]Id,
free_list_begin: std.meta.Int(.unsigned, std.math.log2(pool_size)),
free_list_end: std.meta.Int(.unsigned, std.math.log2(pool_size)),
upload_buffer: sdl3.gpu.TransferBuffer,

pub fn init(
    arena: *std.heap.ArenaAllocator,
    gpu: sdl3.gpu.Device,
) error{ OutOfMemory, SdlError }!Self {
    const textures = try arena.allocator().alloc(Texture, pool_size);

    for (textures) |*texture| {
        texture.* = .init();
    }

    const free_list = try arena.allocator().alloc(Id, pool_size);

    for (free_list, 0..) |*entry, index| {
        entry.* = @intCast(index);
    }

    const upload_buffer = try gpu.createTransferBuffer(.{
        .size = Tmem.max_texture_size,
        .usage = .upload,
    });
    errdefer gpu.releaseTransferBuffer(upload_buffer);

    return .{
        .textures = textures[0..pool_size],
        .free_list = free_list[0..pool_size],
        .free_list_begin = 0,
        .free_list_end = @intCast(free_list.len - 1),
        .upload_buffer = upload_buffer,
    };
}

pub fn deinit(self: *Self, gpu: sdl3.gpu.Device) void {
    gpu.releaseTransferBuffer(self.upload_buffer);
}

pub fn get(self: *const Self, id: Id) *const Texture {
    return &self.textures[id];
}

pub fn create(
    self: *Self,
    gpu: sdl3.gpu.Device,
    width: u32,
    height: u32,
    pixels: []const u8,
) error{SdlError}!u32 {
    std.debug.assert(self.free_list_begin != self.free_list_end);
    const id = self.free_list[self.free_list_begin];
    self.free_list_begin +%= 1;

    fw.log.trace("Texture Create: {} ({})", .{ id, self.textures[id].ref_count });

    try self.textures[id].activate(gpu, self.upload_buffer, width, height, pixels);

    return id;
}

pub fn ref(self: *Self, id: Id) void {
    fw.log.trace("Texture Ref: {} ({})", .{ id, self.textures[id].ref_count });

    self.textures[id].ref();
}

pub fn unref(self: *Self, gpu: sdl3.gpu.Device, id: Id) void {
    const should_free = self.textures[id].unref(gpu);

    fw.log.trace("Texture Unref: {} ({})", .{ id, self.textures[id].ref_count });

    if (!should_free) {
        return;
    }

    fw.log.trace("Texture Destroy: {} ({})", .{ id, self.textures[id].ref_count });

    self.free_list_end +%= 1;
    std.debug.assert(self.free_list_end != self.free_list_begin);
    self.free_list[self.free_list_end] = id;
}
