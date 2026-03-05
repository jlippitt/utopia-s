const std = @import("std");
const fw = @import("framework");
const Tmem = @import("../Tmem.zig");
const Tile = @import("./Tile.zig");

const Self = @This();

deinterleave_buf: *[Tmem.data_len]u64,
decode_buf: *[Tmem.max_texture_size]u8,

pub fn init(arena: *std.heap.ArenaAllocator) error{OutOfMemory}!Self {
    const deinterleave_buf = try arena.allocator().alloc(u64, Tmem.data_len);
    const decode_buf = try arena.allocator().alloc(u8, Tmem.max_texture_size);

    return .{
        .deinterleave_buf = deinterleave_buf[0..Tmem.data_len],
        .decode_buf = decode_buf[0..Tmem.max_texture_size],
    };
}

pub fn decode(
    self: *Self,
    tile: Tile,
    tmem_data: *const [Tmem.data_len]u64,
) error{TextureTooBig}![]const u8 {
    const width = tile.width();
    const height = tile.height();
    const bpp = tile.bitsPerPixel();

    const src_image_size = std.math.divCeil(u32, width * height * bpp, 8) catch unreachable;

    if (src_image_size > Tmem.data_size) {
        fw.log.warn("Texture too big: {} * {} * {}", .{ width, height, bpp });
        return error.TextureTooBig;
    }

    const tmem_width = std.math.divCeil(
        u32,
        tile.width() * tile.bitsPerPixel(),
        64,
    ) catch unreachable;

    self.deinterleave(tile, tmem_width, tmem_data);

    const format = tile.pixelFormat();
    const size = tile.pixelSize();

    const dst_image_size = width * height * 4;

    switch (format) {
        .rgba => switch (size) {
            .@"32" => return std.mem.sliceAsBytes(self.deinterleave_buf)[0..dst_image_size],
            .@"16" => self.decodeFormat(rgba16, tile, tmem_width),
            else => fw.log.unimplemented("Texture format: {t} {t}", .{ format, size }),
        },
        else => fw.log.unimplemented("Texture format: {t} {t}", .{ format, size }),
    }

    return self.decode_buf[0..dst_image_size];
}

fn deinterleave(
    self: *Self,
    tile: Tile,
    tmem_width: u32,
    tmem_data: *const [Tmem.data_len]u64,
) void {
    var dst_index: u32 = 0;
    var src_index = tile.tmemAddress();

    for (0..tile.height()) |line| {
        for (0..tmem_width) |_| {
            var word = tmem_data[src_index & 0x1ff];

            if ((line & 1) != 0) {
                word = std.math.rotl(u64, word, 32);
            }

            self.deinterleave_buf[dst_index] = word;

            dst_index += 1;
            src_index += 1;
        }
    }
}

fn decodeFormat(self: *Self, comptime Format: type, tile: Tile, tmem_width: u32) void {
    const src_data: []const [Format.src_chunk_size]u8 = @ptrCast(
        self.deinterleave_buf[0..(tmem_width * tile.height())],
    );

    const dst_data: [][Format.dst_chunk_size]u8 = @ptrCast(
        self.decode_buf[0..(src_data.len * Format.dst_chunk_size)],
    );

    for (dst_data, src_data) |*dst, src| {
        dst.* = Format.decode(src);
    }
}

pub const rgba16 = struct {
    const dst_chunk_size = 4;
    const src_chunk_size = 2;

    fn decode(src: [2]u8) [4]u8 {
        return fw.color.Rgba16.fromBytesBe(src).toAbgr32Bytes();
    }
};
