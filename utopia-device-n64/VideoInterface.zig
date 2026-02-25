const fw = @import("framework");

const Self = @This();

ctrl: Control = .{},
origin: u24 = 0,
width: u12 = 0,
v_intr: u10 = 0,
burst: Burst = .{},
v_total: u10 = 0,
h_total: HTotal = .{},
h_total_leap: HTotalLeap = .{},
h_video: Range = .{},
v_video: Range = .{},
v_burst: Range = .{},
x_scale: Scale = .{},
y_scale: Scale = .{},

pub fn init() Self {
    return .{};
}

pub fn read(self: *Self, address: u32) u32 {
    return switch (@as(u4, @truncate(address >> 2))) {
        0 => @bitCast(self.ctrl),
        1 => self.origin,
        2 => self.width,
        3 => self.v_intr,
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
        4 => {}, // TODO: VI interrupts
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
    h_total: u12 = 0,
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
};

const Scale = packed struct(u32) {
    scale: u12 = 0,
    __0: u4 = 0,
    offset: u12 = 0,
    __1: u4 = 0,
};
