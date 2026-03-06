const std = @import("std");
const sdl3 = @import("sdl3");
const fw = @import("framework");
const Tmem = @import("../Tmem.zig");
const Texture = @import("./Texture.zig");

const pool_size = 1024;

const LruNode = struct {
    key: u64,
    texture: *Texture,
    node: std.DoublyLinkedList.Node,
};

const TextureMapContext = struct {
    pub fn hash(_: @This(), key: u64) u64 {
        // Value passed in is already hashed
        return key;
    }

    pub fn eql(_: @This(), lhs: u64, rhs: u64) bool {
        return lhs == rhs;
    }
};

const TextureMap = std.HashMapUnmanaged(u64, *std.DoublyLinkedList.Node, TextureMapContext, 50);

const Self = @This();

texture_map: TextureMap,
lru: std.DoublyLinkedList,
upload_buffer: sdl3.gpu.TransferBuffer,

pub fn init(
    arena: *std.heap.ArenaAllocator,
    upload_buffer: sdl3.gpu.TransferBuffer,
) error{ OutOfMemory, SdlError }!Self {
    const textures = try arena.allocator().alloc(Texture, pool_size);

    for (textures) |*texture| {
        texture.* = .init();
    }

    // Map has twice the capacity of the texture pool to help reduce collisions
    var texture_map: TextureMap = .empty;
    try texture_map.ensureTotalCapacity(arena.allocator(), pool_size * 2);

    const lru_nodes = try arena.allocator().alloc(LruNode, pool_size);
    var lru: std.DoublyLinkedList = .{};

    for (lru_nodes, 0..) |*lru_node, index| {
        lru_node.texture = &textures[index];
        lru.append(&lru_node.node);
    }

    return .{
        .texture_map = texture_map,
        .lru = lru,
        .upload_buffer = upload_buffer,
    };
}

pub fn deinit(self: *Self, gpu: sdl3.gpu.Device) void {
    gpu.releaseTransferBuffer(self.upload_buffer);
}

pub fn create(
    self: *Self,
    gpu: sdl3.gpu.Device,
    width: u32,
    height: u32,
    pixels: []const u8,
) error{SdlError}!*Texture {
    var hasher = std.hash.Wyhash.init(0);
    std.hash.autoHashStrat(&hasher, .{ width, height, pixels }, .Deep);
    const key = hasher.final();

    if (self.texture_map.get(key)) |node| {
        const payload: *const LruNode = @alignCast(@fieldParentPtr("node", node));
        std.debug.assert(payload.key == key);
        self.lru.remove(node);
        self.lru.append(node);
        return payload.texture;
    }

    const node = self.lru.popFirst().?;
    const payload: *LruNode = @alignCast(@fieldParentPtr("node", node));
    const texture = payload.texture;

    if (texture.hasRefs()) {
        fw.log.panic("Texture cache full", .{});
    }

    if (texture.isActive()) {
        texture.deactivate(gpu);
        _ = self.texture_map.remove(payload.key);
    }

    try texture.activate(gpu, self.upload_buffer, width, height, pixels);
    self.texture_map.putAssumeCapacity(key, node);
    payload.key = key;
    self.lru.append(node);

    return texture;
}
