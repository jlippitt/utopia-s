const std = @import("std");
const fw = @import("framework");
const Core = @import("./Core.zig");
const Target = @import("./Target.zig");

pub fn syncFull(core: *Core) Core.RenderError!void {
    fw.log.debug("SYNC_FULL", .{});
    try core.downloadImageData();
    return core.getRdp().syncFull();
}

pub fn setScissor(core: *Core, word: u64) void {
    const cmd: SetScissor = @bitCast(word);
    fw.log.debug("SET_SCISSOR: {any}", .{cmd});
    core.target.setImageHeight(cmd.yl.get(u10, 0));
}

pub fn setColorImage(core: *Core, word: u64) void {
    const cmd: SetColorImage = @bitCast(word);

    fw.log.debug("SET_COLOR_IMAGE: {any}", .{cmd});

    const color_format: Target.ColorImageFormat = switch (cmd.format) {
        .rgba => switch (cmd.size) {
            .@"16" => .rgba16,
            .@"32" => .rgba32,
            else => fw.log.unimplemented("Color image RGBA bit depth: {t}", .{cmd.size}),
        },
        else => fw.log.unimplemented("Color image format: {t}", .{cmd.format}),
    };

    core.target.setColorImageParams(cmd.dram_addr, color_format, @as(u32, cmd.width) + 1);
}

pub fn Fixed(comptime T: type, frac: comptime_int) type {
    return packed struct(T) {
        const Self = @This();

        value: T,

        pub fn get(self: Self, comptime Dst: type, dst_frac: comptime_int) Dst {
            const shift = dst_frac - frac;

            if (@bitSizeOf(Dst) >= @bitSizeOf(T)) {
                return std.math.shl(Dst, @as(Dst, self.value), shift);
            }

            return @as(Dst, @truncate(std.math.shl(T, self.value, shift)));
        }

        pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
            const value: f64 = @floatFromInt(self.value);
            const divisor: f64 = @floatFromInt(@as(T, 1) << frac);
            writer.print("{d:." ++ frac ++ "}", .{value / divisor});
        }
    };
}

const SetScissor = packed struct(u64) {
    yl: Fixed(u12, 2),
    xl: Fixed(u12, 2),
    odd_line: bool,
    field: bool,
    __0: u6,
    yh: Fixed(u12, 2),
    xh: Fixed(u12, 2),
    __1: u8,
};

const Size = enum(u2) {
    @"4",
    @"8",
    @"16",
    @"32",
};

const Format = enum(u3) {
    rgba,
    yuv,
    color_index,
    ia,
    i,
};

const SetColorImage = packed struct(u64) {
    dram_addr: u24,
    __0: u8,
    width: u10,
    __1: u9,
    size: Size,
    format: Format,
    __2: u8,
};
