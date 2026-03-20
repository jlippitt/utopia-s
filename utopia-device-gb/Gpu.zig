const std = @import("std");
const fw = @import("framework");
const Device = @import("./Device.zig");

const vram_begin = 80;
const hblank_begin = 240; // TODO: This will vary
const dots_per_line = 456;

const vblank_line = 144;
const total_lines = 154;

const Self = @This();

ctrl: Control = .{},
status: Status = .{},
scroll_y: u8 = 0,
scroll_x: u8 = 0,
line: u8 = 0,
bg_palette: u8 = 0,
obj_palette: [2]u8 = @splat(0),
window_y: u8 = 0,
window_x: u8 = 0,
dot: u32 = 0,

pub fn init() Self {
    return .{};
}

pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("V={d} H={d}", .{ self.line, self.dot });
}

pub fn read(self: *Self, address: u8) u8 {
    return switch (address) {
        0x40 => @bitCast(self.ctrl),
        0x41 => @bitCast(self.status),
        0x42 => self.scroll_y,
        0x43 => self.scroll_x,
        0x44 => self.line,
        0x47 => self.bg_palette,
        0x48 => self.obj_palette[0],
        0x49 => self.obj_palette[1],
        0x4a => self.window_y,
        0x4b => self.window_x,
        else => fw.log.todo("GPU register read: {X:02}", .{address}),
    };
}

pub fn write(self: *Self, address: u8, value: u8) void {
    switch (address) {
        0x40 => {
            const prev_lcd_enable = self.ctrl.lcd_enable;
            self.ctrl = @bitCast(value);
            fw.log.debug("LCD Control: {any}", .{self.ctrl});

            if (!self.ctrl.lcd_enable and prev_lcd_enable) {
                self.status.mode = .oam;
                self.line = 0;
                self.dot = 0;
            }
        },
        0x41 => {
            fw.num.writeMasked(u8, @ptrCast(&self.status), value, 0x78);
            fw.log.debug("LCD Status: {any}", .{self.status});
        },
        0x42 => {
            self.scroll_y = value;
            fw.log.debug("Scroll Y: {d}", .{self.scroll_y});
        },
        0x43 => {
            self.scroll_x = value;
            fw.log.debug("Scroll X: {d}", .{self.scroll_x});
        },
        0x46 => {}, // TODO: OAM DMA
        0x47 => {
            self.bg_palette = value;
            fw.log.debug("BG Palette: {X:02}", .{self.bg_palette});
        },
        0x48 => {
            self.obj_palette[0] = value;
            fw.log.debug("OBJ Palette 0: {X:02}", .{self.obj_palette[0]});
        },
        0x49 => {
            self.obj_palette[1] = value;
            fw.log.debug("OBJ Palette 1: {X:02}", .{self.obj_palette[1]});
        },
        0x4a => {
            self.window_y = value;
            fw.log.debug("Window Y: {d}", .{self.window_y});
        },
        0x4b => {
            self.window_x = value;
            fw.log.debug("Window X: {d}", .{self.window_x});
        },
        else => fw.log.todo("GPU register write: {X:02}", .{address}),
    }
}

pub fn step(self: *Self, cycles: u64) void {
    if (!self.ctrl.lcd_enable) {
        return;
    }

    for (0..cycles) |_| {
        switch (self.status.mode) {
            .hblank => {
                if (self.dot == dots_per_line) {
                    self.dot = 0;
                    self.line += 1;

                    if (self.line == vblank_line) {
                        self.status.mode = .vblank;
                        self.getDevice().interrupt.raise(.vblank);
                    } else {
                        self.status.mode = .oam;
                    }
                } else {
                    self.dot += 1;
                }
            },
            .vblank => {
                if (self.dot == dots_per_line) {
                    self.dot = 0;
                    self.line += 1;

                    if (self.line == total_lines) {
                        self.line = 0;
                        self.status.mode = .oam;
                    }
                } else {
                    self.dot += 1;
                }
            },
            .oam => {
                // TODO: Select sprites
                if (self.dot == vram_begin) {
                    self.status.mode = .vram;
                }

                self.dot += 1;
            },
            .vram => {
                // TODO: Render
                if (self.dot == hblank_begin) {
                    self.status.mode = .hblank;
                }

                self.dot += 1;
            },
        }
    }
}

fn getDevice(self: *Self) *Device {
    return @alignCast(@fieldParentPtr("gpu", self));
}

const Control = packed struct(u8) {
    bg_enable: bool = false,
    obj_enable: bool = false,
    obj_size: bool = false,
    bg_tile_map: bool = false,
    bg_chr_map: bool = false,
    window_enable: bool = false,
    window_tile_map: bool = false,
    lcd_enable: bool = false,
};

const Mode = enum(u2) {
    hblank,
    vblank,
    oam,
    vram,
};

const Status = packed struct(u8) {
    mode: Mode = .oam,
    lyc: bool = false,
    int_hblank: bool = false,
    int_vblank: bool = false,
    int_oam: bool = false,
    int_lyc: bool = false,
    __: bool = false,
};
