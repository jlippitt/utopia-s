const std = @import("std");
const sdl3 = @import("sdl3");
const fw = @import("framework");
const Tmem = @import("../Tmem.zig");
const Texture = @import("./Texture.zig");

const pool_size = 1024;

const Self = @This();

lru: fw.lru.Lru(u64, Texture),
upload_buffer: sdl3.gpu.TransferBuffer,

pub fn init(
    arena: *std.heap.ArenaAllocator,
    upload_buffer: sdl3.gpu.TransferBuffer,
) error{ OutOfMemory, SdlError }!Self {
    return .{
        .lru = try .init(arena.allocator(), pool_size, .{}),
        .upload_buffer = upload_buffer,
    };
}

pub fn deinit(self: *Self, gpu: sdl3.gpu.Device) void {
    gpu.releaseTransferBuffer(self.upload_buffer);
}

pub fn getOrInsert(
    self: *Self,
    gpu: sdl3.gpu.Device,
    width: u32,
    height: u32,
    pixels: []const u8,
) error{SdlError}!*Texture {
    var hasher = std.hash.Wyhash.init(0);
    std.hash.autoHashStrat(&hasher, .{ width, height, pixels }, .Deep);
    const key = hasher.final();

    const result = self.lru.getOrPut(key);
    const texture = result.value_ptr;

    if (result.found_existing) {
        return texture;
    }

    if (texture.hasRefs()) {
        fw.log.panic("Texture cache full", .{});
    }

    if (texture.isActive()) {
        texture.deactivate(gpu);
    }

    try texture.activate(gpu, self.upload_buffer, width, height, pixels);

    return texture;
}
