const std = @import("std");
const fw = @import("framework");
const Device = @import("./Device.zig");
const Clock = @import("./Clock.zig");
const Rdp = @import("./Rdp.zig");

const default_width = 640;
const default_height = 474;
const default_h_total = 3093;
const default_v_total = 525;
const pixel_array_size = default_width * default_height * 4;

const Self = @This();

ctrl: Control = .{},
origin: u24 = 0,
width: u12 = 0,
v_current: u10 = 0,
v_intr: u10 = 0,
burst: Burst = .{},
v_total: u10 = default_v_total,
h_total: HTotal = .{},
h_total_leap: HTotalLeap = .{},
h_video: Range = .{},
v_video: Range = .{},
v_burst: Range = .{},
x_scale: Scale = .{},
y_scale: Scale = .{},
cycles_per_line: u64 = 0,
resolution: fw.Resolution = .{
    .x = default_width,
    .y = default_height,
},
pixels: *[pixel_array_size]u8,

pub fn init(arena: *std.heap.ArenaAllocator, clock: *Clock) !Self {
    const pixels = try arena.allocator().alloc(u8, pixel_array_size);

    const cycles_per_line = calcCyclesPerLine(default_h_total);
    fw.log.debug("Cycles Per Line: {}", .{cycles_per_line});
    clock.schedule(.vi_new_line, cycles_per_line);

    return .{
        .cycles_per_line = cycles_per_line,
        .pixels = pixels[0..pixel_array_size],
    };
}

pub fn getVideoState(self: *const Self) fw.VideoState {
    return .{
        .resolution = self.resolution,
        .pixel_data = self.pixels,
    };
}

pub fn read(self: *Self, address: u32) u32 {
    return switch (@as(u4, @truncate(address >> 2))) {
        0 => @bitCast(self.ctrl),
        1 => self.origin,
        2 => self.width,
        3 => self.v_intr,
        4 => self.v_current,
        5 => @bitCast(self.burst),
        6 => self.v_total,
        7 => @bitCast(self.h_total),
        8 => @bitCast(self.h_total_leap),
        9 => @bitCast(self.h_video),
        10 => @bitCast(self.v_video),
        11 => @bitCast(self.v_burst),
        12 => @bitCast(self.x_scale),
        13 => @bitCast(self.y_scale),
        else => fw.log.panic("Unmapped VI register read: {X:08}", .{address}),
    };
}

pub fn write(self: *Self, address: u32, value: u32, mask: u32) void {
    switch (@as(u4, @truncate(address >> 2))) {
        0 => {
            fw.num.writeMasked(u32, @ptrCast(&self.ctrl), value, mask);
            fw.log.debug("VI_CTRL: {any}", .{self.ctrl});
        },
        1 => {
            fw.num.writeMasked(u24, &self.origin, @truncate(value), @truncate(mask));
            fw.log.debug("VI_ORIGIN: {X:08}", .{self.origin});
        },
        2 => {
            fw.num.writeMasked(u12, &self.width, @truncate(value), @truncate(mask));
            fw.log.debug("VI_WIDTH: {d}", .{self.width});
        },
        3 => {
            fw.num.writeMasked(u10, &self.v_intr, @truncate(value), @truncate(mask));
            fw.log.debug("VI_V_INTR: {d}", .{self.v_intr});
        },
        4 => self.getDevice().mi.clearInterrupt(.vi),
        5 => {
            fw.num.writeMasked(u32, @ptrCast(&self.burst), value, mask);
            fw.log.debug("VI_BURST: {any}", .{self.burst});
        },
        6 => {
            fw.num.writeMasked(u10, &self.v_total, @truncate(value), @truncate(mask));
            fw.log.debug("VI_V_TOTAL: {d}", .{self.v_total});
        },
        7 => {
            fw.num.writeMasked(u32, @ptrCast(&self.h_total), value, mask);
            fw.log.debug("H_TOTAL: {any}", .{self.h_total});

            const cycles_per_line = calcCyclesPerLine(self.h_total.h_total);

            if (cycles_per_line != self.cycles_per_line) {
                self.cycles_per_line = cycles_per_line;
                fw.log.debug("Cycles Per Line: {}", .{self.cycles_per_line});
                self.getDevice().clock.reschedule(.vi_new_line, cycles_per_line);
            }
        },
        8 => {
            fw.num.writeMasked(u32, @ptrCast(&self.h_total_leap), value, mask);
            fw.log.debug("H_TOTAL_LEAP: {any}", .{self.h_total_leap});
        },
        9 => {
            fw.num.writeMasked(u32, @ptrCast(&self.h_video), value, mask);
            fw.log.debug("VI_H_VIDEO: {any}", .{self.h_video});
        },
        10 => {
            fw.num.writeMasked(u32, @ptrCast(&self.v_video), value, mask);
            fw.log.debug("VI_V_VIDEO: {any}", .{self.v_video});
        },
        11 => {
            fw.num.writeMasked(u32, @ptrCast(&self.v_burst), value, mask);
            fw.log.debug("VI_V_BURST: {any}", .{self.v_burst});
        },
        12 => {
            fw.num.writeMasked(u32, @ptrCast(&self.x_scale), value, mask);
            fw.log.debug("VI_X_SCALE: {any}", .{self.x_scale});
        },
        13 => {
            fw.num.writeMasked(u32, @ptrCast(&self.y_scale), value, mask);
            fw.log.debug("VI_Y_SCALE: {any}", .{self.y_scale});
        },
        else => fw.log.panic("Unmapped VI register write: {X:08} <= {X:08}", .{ address, value }),
    }
}

pub fn handleNewLineEvent(self: *Self) Rdp.RenderError!bool {
    var frame_complete: bool = false;

    self.v_current += 2;

    if (self.v_current >= self.v_total) {
        const serrate: u10 = @intFromBool(self.ctrl.serrate);
        self.v_current = self.v_current & serrate ^ serrate;
        try self.getDevice().rdp.downloadImageData();
        self.render();
        frame_complete = true;
    }

    fw.log.trace("VI_V_CURRENT: {}", .{self.v_current});

    if (self.v_current == self.v_intr) {
        self.getDevice().mi.raiseInterrupt(.vi);
    }

    self.getDevice().clock.schedule(.vi_new_line, self.cycles_per_line);

    return frame_complete;
}

fn render(self: *Self) void {
    const dst_width = @as(u32, self.h_video.size()) * @as(u32, self.x_scale.scale) / 1024;
    const dst_height = @as(u32, self.v_video.size()) * @as(u32, self.y_scale.scale) / 2048;

    var color_mode: ColorMode = .blank;

    if (dst_width != 0 and dst_height != 0) {
        color_mode = self.ctrl.color_mode;
        self.resolution = .{ .x = dst_width, .y = dst_height };
    }

    fw.log.debug("Rendering Frame: {d}x{d} ({t})", .{
        dst_width,
        dst_height,
        color_mode,
    });

    switch (color_mode) {
        .blank => @memset(self.pixels, 0),
        .rgba16 => {
            const rdram = self.getDeviceConst().rdram;
            const dst_pitch = dst_width * 4;
            const src_pitch = @as(u32, self.width) * 4;
            const min_pitch = @min(dst_pitch, src_pitch);

            var dst_index: u32 = 0;
            var src_index: u32 = self.origin;

            for (0..dst_height) |_| {
                const dst_data: [][4]u8 = @ptrCast(self.pixels[dst_index..][0..min_pitch]);
                const src_data: []const [2]u8 = @ptrCast(rdram[src_index..][0..(min_pitch / 2)]);

                for (dst_data, src_data) |*dst, src| {
                    dst.* = fw.color.Rgba16.fromBytesBe(src).toAbgr32Bytes();
                }

                @memset(
                    self.pixels[(dst_index + min_pitch)..(dst_index + dst_pitch)],
                    0,
                );

                dst_index += dst_pitch;
                src_index += src_pitch / 2;
            }
        },
        .rgba32 => {
            const rdram = self.getDeviceConst().rdram;
            const dst_pitch = dst_width * 4;
            const src_pitch = @as(u32, self.width) * 4;
            const min_pitch = @min(dst_pitch, src_pitch);

            var dst_index: u32 = 0;
            var src_index: u32 = self.origin;

            for (0..dst_height) |_| {
                @memcpy(
                    self.pixels[dst_index..][0..min_pitch],
                    rdram[src_index..][0..min_pitch],
                );

                @memset(
                    self.pixels[(dst_index + min_pitch)..(dst_index + dst_pitch)],
                    0,
                );

                dst_index += dst_pitch;
                src_index += src_pitch;
            }
        },
        else => fw.log.unimplemented("Color mode: {t}", .{color_mode}),
    }
}

fn getDevice(self: *Self) *Device {
    return @alignCast(@fieldParentPtr("vi", self));
}

fn getDeviceConst(self: *Self) *const Device {
    return @alignCast(@fieldParentPtr("vi", self));
}

fn calcCyclesPerLine(h_total: u12) u64 {
    return @intFromFloat(
        @as(f64, @floatFromInt(
            Device.clock_rate * (@as(u64, h_total) + 1),
        )) / Device.video_dac_rate,
    );
}

const ColorMode = enum(u2) {
    blank,
    reserved,
    rgba16,
    rgba32,
};

const AntiAliasMode = enum(u2) {
    replicate,
    resample,
    aa_needed,
    aa_always,
};

const Control = packed struct(u32) {
    color_mode: ColorMode = .blank,
    gamma_dither_enable: bool = false,
    gamma_enable: bool = false,
    divot_enable: bool = false,
    vbus_clock_enable: bool = false,
    serrate: bool = false,
    test_mode: bool = false,
    aa_mode: AntiAliasMode = .replicate,
    __0: u1 = 0,
    kill_we: bool = false,
    pixel_advance: u4 = 0,
    dedither_filter_enable: bool = false,
    __1: u15 = 0,
};

const Burst = packed struct(u32) {
    hsync_width: u8 = 0,
    burst_width: u8 = 0,
    vsync_height: u4 = 0,
    burst_start: u10 = 0,
    __: u2 = 0,
};

const HTotal = packed struct(u32) {
    h_total: u12 = default_h_total,
    __0: u4 = 0,
    leap: u5 = 0,
    __1: u11 = 0,
};

const HTotalLeap = packed struct(u32) {
    leap_a: u12 = 0,
    __0: u4 = 0,
    leap_b: u12 = 0,
    __1: u4 = 0,
};

const Range = packed struct(u32) {
    end: u10 = 0,
    __0: u6 = 0,
    start: u10 = 0,
    __1: u6 = 0,

    fn size(self: @This()) u10 {
        return self.end - self.start;
    }
};

const Scale = packed struct(u32) {
    scale: u12 = 0,
    __0: u4 = 0,
    offset: u12 = 0,
    __1: u4 = 0,
};
