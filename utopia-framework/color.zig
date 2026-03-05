const std = @import("std");

pub const Rgba16 = packed struct(u16) {
    const Self = @This();

    a: u1 = 0,
    b: u5 = 0,
    g: u5 = 0,
    r: u5 = 0,

    pub fn fromUint(other: u16) Self {
        return @bitCast(other);
    }

    pub fn fromBytesLe(other: [2]u8) Self {
        return @bitCast(other);
    }

    pub fn fromBytesBe(other: [2]u8) Self {
        return fromUint(@byteSwap(@as(u16, @bitCast(other))));
    }

    pub fn fromAbgr32(other: Abgr32) Self {
        return .{
            .r = @truncate(other.r >> 3),
            .g = @truncate(other.g >> 3),
            .b = @truncate(other.b >> 3),
            .a = @truncate(other.a >> 7),
        };
    }

    pub fn fromAbgr32Bytes(other: [4]u8) Self {
        return fromAbgr32(@bitCast(other));
    }

    pub fn toUint(self: Self) u16 {
        return @bitCast(self);
    }

    pub fn toBytesLe(self: Self) [2]u8 {
        return @bitCast(self);
    }

    pub fn toBytesBe(self: Self) [2]u8 {
        return @bitCast(@byteSwap(self.toUint()));
    }

    pub fn toAbgr32(self: Self) Abgr32 {
        return .fromRgba16(self);
    }

    pub fn toAbgr32Bytes(self: Self) [4]u8 {
        return @bitCast(self.toAbgr32());
    }
};

pub const Rgba32 = packed struct(u32) {
    const Self = @This();

    a: u8 = 0,
    b: u8 = 0,
    g: u8 = 0,
    r: u8 = 0,
};

pub const Abgr32 = packed struct(u32) {
    const Self = @This();

    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 0,

    pub fn fromRgba16(other: Rgba16) Self {
        return .{
            .r = @as(u8, other.r) << 3,
            .g = @as(u8, other.g) << 3,
            .b = @as(u8, other.b) << 3,
            .a = std.math.boolMask(u8, other.a != 0),
        };
    }
};

pub const RgbaUnorm = extern struct {
    const Self = @This();

    r: f32 = 0.0,
    g: f32 = 0.0,
    b: f32 = 0.0,
    a: f32 = 0.0,

    pub fn fromR8(other: u8) Self {
        const intensity = @as(f32, @floatFromInt(other)) / 255.0;

        return .{
            .r = intensity,
            .g = intensity,
            .b = intensity,
            .a = intensity,
        };
    }

    pub fn fromRgba16(other: Rgba16) Self {
        return .{
            .r = @as(f32, @floatFromInt(other.r)) / 31.0,
            .g = @as(f32, @floatFromInt(other.g)) / 31.0,
            .b = @as(f32, @floatFromInt(other.b)) / 31.0,
            .a = @as(f32, @floatFromInt(other.a)),
        };
    }

    pub fn fromRgba16Uint(other: u16) Self {
        return fromRgba16(@bitCast(other));
    }

    pub fn fromRgba32(other: Rgba32) Self {
        return .{
            .r = @as(f32, @floatFromInt(other.r)) / 255.0,
            .g = @as(f32, @floatFromInt(other.g)) / 255.0,
            .b = @as(f32, @floatFromInt(other.b)) / 255.0,
            .a = @as(f32, @floatFromInt(other.a)) / 255.0,
        };
    }

    pub fn fromRgba32Uint(other: u32) Self {
        return fromRgba32(@bitCast(other));
    }
};
