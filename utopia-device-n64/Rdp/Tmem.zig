const std = @import("std");
const sdl3 = @import("sdl3");
const fw = @import("framework");
const Decoder = @import("./Tmem/Decoder.zig");
const TexturePool = @import("./Tmem/TexturePool.zig");

pub const Tile = @import("./Tmem/Tile.zig");
pub const Texture = TexturePool.Id;
pub const TlutType = Decoder.TlutType;

pub const data_len = 512;
pub const data_size = data_len * 8;

// 4bpp texture expands to 8 RGBA32 bytes per TMEM byte
pub const max_texture_size = data_size * 8;

const Self = @This();

data: *[data_len]u64,
decoder: Decoder,
texture_pool: TexturePool,
null_texture: Texture,
image_width: u24 = 0,
image_address: u24 = 0,
tlut_type: TlutType = .rgba,
tiles: [8]Tile = @splat(.init()),

pub fn init(
    arena: *std.heap.ArenaAllocator,
    gpu: sdl3.gpu.Device,
) error{ OutOfMemory, SdlError }!Self {
    const data = try arena.allocator().alloc(u64, data_len);

    var texture_pool = try TexturePool.init(arena, gpu);
    errdefer texture_pool.deinit(gpu);

    const null_texture = try texture_pool.create(gpu, 1, 1, &.{ 0, 0, 0, 0 });

    return .{
        .data = data[0..data_len],
        .decoder = try .init(arena),
        .texture_pool = texture_pool,
        .null_texture = null_texture,
    };
}

pub fn deinit(self: *Self, gpu: sdl3.gpu.Device) void {
    self.texture_pool.unref(gpu, self.null_texture);
    self.texture_pool.deinit(gpu);
}

pub fn getTile(self: *const Self, index: u3) Tile {
    return self.tiles[index];
}

pub fn getBinding(self: *Self, texture: Texture) sdl3.gpu.Texture {
    return self.texture_pool.get(texture).getBinding();
}

pub fn nullTexture(self: *Self) Texture {
    self.texture_pool.ref(self.null_texture);
    return self.null_texture;
}

pub fn createTexture(self: *Self, gpu: sdl3.gpu.Device, index: u3) error{SdlError}!Texture {
    const tile = self.tiles[index];

    const pixels = self.decoder.decode(tile, self.data, self.tlut_type) catch |err| {
        switch (err) {
            error.TextureTooBig => fw.log.warn("Texture too big: {} * {} * {}", .{
                tile.width(),
                tile.height(),
                tile.bitsPerPixel(),
            }),
            error.FormatNotSupported => fw.log.warn("Texture format unsupported: {t} {t}", .{
                tile.pixelFormat(),
                tile.pixelSize(),
            }),
        }

        return self.nullTexture();
    };

    return self.texture_pool.create(gpu, tile.width(), tile.height(), pixels);
}

pub fn refTexture(self: *Self, texture: Texture) void {
    self.texture_pool.ref(texture);
}

pub fn unrefTexture(self: *Self, gpu: sdl3.gpu.Device, texture: Texture) void {
    self.texture_pool.unref(gpu, texture);
}

pub fn setImageParams(self: *Self, address: u24, width: u24) void {
    self.image_address = address;
    fw.log.debug("Image Address: {X:08}", .{self.image_address});

    self.image_width = width;
    fw.log.debug("Image Width: {d}", .{self.image_width});
}

pub fn setTlutType(self: *Self, tlut_type: TlutType) void {
    self.tlut_type = tlut_type;
    fw.log.debug("TLUT Type: {t}", .{tlut_type});
}

pub fn setTileDescriptor(self: *Self, desc: Tile.Descriptor) void {
    const index = desc.tile;
    self.tiles[index].desc = desc;
    fw.log.debug("Tile {d} Descriptor: {any}", .{ index, self.tiles[index].desc });
}

pub fn setTileSize(self: *Self, size: Tile.Size) void {
    const index = size.tile;
    self.tiles[index].size = size;
    fw.log.debug("Tile {d} Size: {any}", .{ index, self.tiles[index].size });
}

pub fn loadTlut(self: *Self, rdram: []const u8, size: Tile.Size) void {
    // Note: Loading TLUT data does not update the size of stored tile
    var tile = self.tiles[size.tile];
    tile.size = size;

    const dram_addr: u32 = self.image_address;
    const tmem_addr = tile.tmemAddress();

    const width = tile.width() * tile.height();
    const dst_data = self.data[tmem_addr..][0..width];
    const src_data: []const [2]u8 = @ptrCast(rdram[dram_addr..][0..(width * 2)]);

    for (dst_data, src_data) |*dst, src| {
        const color = (@as(u64, src[0]) << 8) | src[1];
        dst.* = (color << 48) | (color << 32) | (color << 16) | color;
    }

    fw.log.debug("TLUT data uploaded from {X:08}..{X:08} to {X:03}..{X:03} ({}x{} words = {} bytes)", .{
        dram_addr,
        dram_addr + width * 2,
        tmem_addr * 8,
        (tmem_addr + width) * 8,
        tile.width(),
        tile.height(),
        width * 8,
    });
}

pub fn loadTile(self: *Self, rdram: []const u8, size: Tile.Size) void {
    self.setTileSize(size);

    const tile = self.tiles[size.tile];

    const bpp = tile.bitsPerPixel();

    const dram_x_offset = std.math.divCeil(u32, tile.x() * bpp, 8) catch unreachable;
    const dram_width = std.math.divCeil(u32, @as(u32, self.image_width) * bpp, 8) catch unreachable;
    const dram_y_offset = tile.y() * dram_width;
    const dram_begin = @as(u32, self.image_address) + dram_y_offset;
    var dram_addr = dram_begin;

    const tmem_width = std.math.divCeil(u32, @min(tile.width(), self.image_width) * bpp, 64) catch unreachable;
    var tmem_addr = tile.tmemAddress();

    for (0..tile.height()) |line| {
        const dst_data = self.data[tmem_addr..][0..tmem_width];
        const src_data = rdram[(dram_addr + dram_x_offset)..][0..(tmem_width * 8)];

        @memcpy(std.mem.sliceAsBytes(dst_data), src_data);

        if ((line & 1) != 0) {
            for (dst_data) |*word| {
                word.* = std.math.rotl(u64, word.*, 32);
            }
        }

        dram_addr += dram_width;
        tmem_addr += tmem_width;
    }

    fw.log.debug("Tile data uploaded from {X:08}..{X:08} to {X:03}..{X:03} ({}x{} words = {} bytes)", .{
        dram_begin,
        dram_addr,
        tile.tmemAddress() * 8,
        tmem_addr * 8,
        tmem_width,
        tile.height(),
        tmem_width * tile.height() * 8,
    });
}

pub fn loadBlock(self: *Self, rdram: []const u8, size: Tile.Size) void {
    // Loading block data does not update the size of stored tile
    const tile = self.tiles[size.tile];

    const dxt = size.th;

    if (dxt == 0 and size.tl != 0) {
        fw.log.panic("Cannot upload block with DXT == 0 and TL != 0", .{});
    }

    const bpp = tile.bitsPerPixel();

    const dram_y_offset = if (dxt != 0)
        @as(u32, size.tl) * (std.math.divCeil(u32, 2048, dxt) catch unreachable) * 8
    else
        0;

    const dram_x_offset = std.math.divCeil(u32, size.sl, 8) catch unreachable;
    const dram_begin = @as(u32, self.image_address + dram_y_offset + dram_x_offset);
    var dram_addr = dram_begin;

    const tmem_width = std.math.divCeil(u32, (@as(u32, size.sh) - size.sl + 1) * bpp, 64) catch unreachable;
    const tmem_begin = tile.tmemAddress();
    const tmem_end = tmem_begin + tmem_width;
    var tmem_addr = tmem_begin;

    var t_pos: u32 = 0;

    while (tmem_addr < tmem_end) {
        {
            const tmem_line_begin = tmem_addr;
            const dram_line_begin = dram_addr;

            while ((t_pos & 0x0800) == 0 and tmem_addr < tmem_end) {
                tmem_addr += 1;
                dram_addr += 8;
                t_pos += dxt;
            }

            const dst_data = self.data[tmem_line_begin..tmem_addr];
            const src_data = rdram[dram_line_begin..dram_addr];
            @memcpy(std.mem.sliceAsBytes(dst_data), src_data);
        }

        if (tmem_addr >= tmem_end) {
            break;
        }

        {
            const tmem_line_begin = tmem_addr;
            const dram_line_begin = dram_addr;

            while ((t_pos & 0x0800) != 0 and tmem_addr < tmem_end) {
                tmem_addr += 1;
                dram_addr += 8;
                t_pos += dxt;
            }

            const dst_data = self.data[tmem_line_begin..tmem_addr];
            const src_data = rdram[dram_line_begin..dram_addr];
            @memcpy(std.mem.sliceAsBytes(dst_data), src_data);

            for (dst_data) |*word| {
                word.* = std.math.rotl(u64, word.*, 32);
            }
        }
    }

    fw.log.debug("Block data uploaded from {X:08}..{X:08} to {X:03}..{X:03} ({} words = {} bytes)", .{
        dram_begin,
        dram_addr,
        tmem_begin * 8,
        tmem_addr * 8,
        tmem_addr - tmem_begin,
        dram_addr - dram_begin,
    });
}
