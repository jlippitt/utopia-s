const Core = @import("../Core.zig");

pub const Descriptor = packed struct(u64) {
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

pub const Size = packed struct(u64) {
    th: u12 = 0,
    sh: u12 = 0,
    tile: u3 = 0,
    __0: u5 = 0,
    tl: u12 = 0,
    sl: u12 = 0,
    __1: u8 = 0,
};

const Self = @This();

desc: Descriptor = .{},
size: Size = .{},

pub fn init() Self {
    return .{};
}

pub fn tmemAddress(self: *const Self) u32 {
    return @as(u32, self.desc.tmem_addr);
}

pub fn pixelFormat(self: *const Self) Core.PixelFormat {
    return self.desc.format;
}

pub fn pixelSize(self: *const Self) Core.PixelSize {
    return self.desc.size;
}

pub fn bitsPerPixel(self: *const Self) u32 {
    return @as(u32, 4) << @intFromEnum(self.desc.size);
}

pub fn palette(self: *const Self) u32 {
    return self.desc.palette;
}

pub fn x(self: *const Self) u32 {
    return self.size.sl >> 2;
}

pub fn y(self: *const Self) u32 {
    return self.size.tl >> 2;
}

pub fn width(self: *const Self) u32 {
    return @as(u32, self.size.sh >> 2) - self.x() + 1;
}

pub fn height(self: *const Self) u32 {
    return @as(u32, self.size.th >> 2) - self.y() + 1;
}
