const sdl3 = @import("sdl3");
const fw = @import("framework");
const Core = @import("./Core.zig");

const Self = @This();

tiles: [8]Tile = @splat(.{}),

pub fn init(gpu: sdl3.gpu.Device) error{SdlError}!Self {
    _ = gpu;
    return .{};
}

pub fn deinit(self: *Self, gpu: sdl3.gpu.Device) void {
    _ = self;
    _ = gpu;
}

pub fn setTileDescriptor(self: *Self, desc: TileDescriptor) void {
    const index = desc.tile;
    self.tiles[index].desc = desc;
    fw.log.debug("Tile {d} Descriptor: {any}", .{ index, self.tiles[index].desc });
}

pub fn setTileSize(self: *Self, size: TileSize) void {
    const index = size.tile;
    self.tiles[index].size = size;
    fw.log.debug("Tile {d} Size: {any}", .{ index, self.tiles[index].size });
}

pub const Tile = struct {
    desc: TileDescriptor = .{},
    size: TileSize = .{},
};

pub const TileDescriptor = packed struct(u64) {
    shift_s: u4 = 0,
    mask_s: u4 = 0,
    mirror_s: bool = false,
    clamp_s: bool = false,
    shift_t: u4 = 0,
    mask_t: u4 = 0,
    mirror_t: bool = false,
    clamp_t: bool = false,
    palette: u4 = 0,
    tile: u3 = 0,
    __0: u5 = 0,
    tmem_addr: u9 = 0,
    line: u9 = 0,
    __1: u1 = 0,
    size: Core.PixelSize = .@"4",
    format: Core.PixelFormat = .rgba,
    __2: u8 = 0,
};

pub const TileSize = packed struct(u64) {
    th: u12 = 0,
    sh: u12 = 0,
    tile: u3 = 0,
    __0: u5 = 0,
    tl: u12 = 0,
    sl: u12 = 0,
    __1: u8 = 0,
};
