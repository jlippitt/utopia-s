const std = @import("std");
const fw = @import("framework");
const Device = @import("./Device.zig");
const background = @import("./Gpu/background.zig");
const object = @import("./Gpu/object.zig");

const render_cycle = 80;
const cycles_per_line = 456;

const vblank_line = 144;
const total_lines = 154;

const vram_size = 8192;
const vram_mask = vram_size - 1;

const oam_size = 160;

const width = 160;
const height = 144;
const pixel_array_size = width * height * 4;

const colors: [4]fw.color.Abgr32 = .{
    .{ .r = 0xff, .g = 0xff, .b = 0xff, .a = 0xff },
    .{ .r = 0xaa, .g = 0xaa, .b = 0xaa, .a = 0xff },
    .{ .r = 0x55, .g = 0x55, .b = 0x55, .a = 0xff },
    .{ .r = 0x00, .g = 0x00, .b = 0x00, .a = 0xff },
};

pub const Tile = struct {
    chr_low: u8 = 0,
    chr_high: u8 = 0,
};

const Self = @This();

ctrl: Control = .{},
status: Status = .{},
scroll_y: u8 = 0,
scroll_x: u8 = 0,
line: u8 = 0,
line_compare: u8 = 0,
bg_palette: u8 = 0,
obj_palette: [2]u8 = @splat(0),
window_y: u8 = 0,
window_x: u8 = 0,
cycle: u32 = 0,
dot: u8 = 0,
pixels: *[pixel_array_size]u8,
pixel_index: u32 = 0,
vram: *[vram_size]u8,
oam: *[oam_size]u8,
name_latch: u8 = 0,
tile_latch: Tile = .{},
bg: background.State = .{},
obj: object.State = .{},

pub fn init(arena: *std.heap.ArenaAllocator) error{OutOfMemory}!Self {
    const pixels = try arena.allocator().alloc(u8, pixel_array_size);
    const vram = try arena.allocator().alloc(u8, vram_size);
    const oam = try arena.allocator().alloc(u8, oam_size);

    return .{
        .pixels = pixels[0..pixel_array_size],
        .vram = vram[0..vram_size],
        .oam = oam[0..oam_size],
    };
}

pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("V={d} H={d}", .{ self.line, self.cycle });
}

pub fn getVideoState(self: *const Self) fw.VideoState {
    return .{
        .resolution = .{ .x = width, .y = height },
        .scale_mode = .integer,
        .pixel_data = self.pixels,
    };
}

pub fn frameDone(self: *const Self) bool {
    return self.pixel_index >= pixel_array_size;
}

pub fn beginFrame(self: *Self) void {
    self.pixel_index = 0;
}

pub fn read(self: *Self, address: u8) u8 {
    return switch (address) {
        0x40 => @bitCast(self.ctrl),
        0x41 => @bitCast(self.status),
        0x42 => self.scroll_y,
        0x43 => self.scroll_x,
        0x44 => self.line,
        0x45 => self.line_compare,
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
                fw.log.debug("Screen Off", .{});
                self.status.mode = .hblank;
                self.line = 0;
                self.cycle = 0;
                self.pixel_index = 0;
            } else if (self.ctrl.lcd_enable and !prev_lcd_enable) {
                fw.log.debug("Screen On", .{});
                self.nextMode(.oam_search);
                self.bg.beginFrame();
                self.renderBegin();
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
        0x44 => {}, // Read-only
        0x45 => {
            self.line_compare = value;
            fw.log.debug("Line Compare: {d}", .{self.line_compare});
        },
        0x46 => self.getDevice().requestOamDma(value),
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

pub fn readVram(self: *Self, address: u16) u8 {
    return self.vram[address & vram_mask];
}

pub fn writeVram(self: *Self, address: u16, value: u8) void {
    self.vram[address & vram_mask] = value;
}

pub fn readOam(self: *Self, address: u8) u8 {
    return self.oam[address];
}

pub fn writeOam(self: *Self, address: u8, value: u8) void {
    self.oam[address] = value;
}

pub fn step(self: *Self, cycles: u64) void {
    if (!self.ctrl.lcd_enable) {
        return;
    }

    for (0..cycles) |_| {
        switch (self.status.mode) {
            .hblank => {
                if (self.cycle == cycles_per_line) {
                    self.nextLine();

                    if (self.line == vblank_line) {
                        self.nextMode(.vblank);
                        self.getDevice().interrupt.raise(.vblank);
                    } else {
                        self.nextMode(.oam_search);
                        self.renderBegin();
                    }
                } else {
                    self.cycle += 1;
                }
            },
            .vblank => {
                if (self.cycle == cycles_per_line) {
                    self.nextLine();

                    if (self.line == 0) {
                        self.nextMode(.oam_search);
                        self.bg.beginFrame();
                        self.renderBegin();
                    }
                } else {
                    self.cycle += 1;
                }
            },
            .oam_search => {
                if (self.cycle == render_cycle) {
                    object.selectSprites(self);
                    self.nextMode(.render);
                }

                self.cycle += 1;
            },
            .render => {
                if (self.renderPixel()) {
                    self.nextMode(.hblank);
                }

                self.cycle += 1;
            },
        }
    }
}

fn nextLine(self: *Self) void {
    self.cycle = 0;
    self.line += 1;

    if (self.line == total_lines) {
        self.line = 0;
    }

    if (self.line == self.line_compare and self.status.int_lyc) {
        self.getDevice().interrupt.raise(.lcd_stat);
    }
}

fn nextMode(self: *Self, mode: Mode) void {
    self.status.mode = mode;

    const interrupt = switch (mode) {
        .hblank => self.status.int_hblank,
        .vblank => self.status.int_vblank,
        .oam_search => self.status.int_oam,
        .render => false,
    };

    if (interrupt) {
        self.getDevice().interrupt.raise(.lcd_stat);
    }
}

fn renderBegin(self: *Self) void {
    self.dot = 0;
    self.obj.beginLine();
    background.beginLine(self);
}

fn renderPixel(self: *Self) bool {
    if (object.loadTiles(self)) {
        return false;
    }

    background.loadTiles(self);

    const bg_pixel = self.bg.popPixel() orelse {
        return false;
    };

    const color: u2 = blk: {
        if (self.obj.popPixel()) |pixel| {
            if (self.ctrl.obj_enable and
                pixel.value != 0 and
                (!pixel.below_bg or bg_pixel == 0))
            {
                break :blk getColor(self.obj_palette[pixel.palette], pixel.value);
            }
        }

        if (self.ctrl.bg_enable) {
            break :blk getColor(self.bg_palette, bg_pixel);
        }

        break :blk 0;
    };

    self.drawPixel(color);
    self.dot += 1;

    return self.dot == width;
}

fn drawPixel(self: *Self, color_index: u2) void {
    const color = colors[color_index];
    const pixel: *[4]u8 = self.pixels[self.pixel_index..][0..4];
    pixel.* = @bitCast(color);
    self.pixel_index += 4;
}

fn getDevice(self: *Self) *Device {
    return @alignCast(@fieldParentPtr("gpu", self));
}

fn getColor(palette: u8, index: u2) u2 {
    return @truncate(palette >> (@as(u3, index) << 1));
}

const Control = packed struct(u8) {
    bg_enable: bool = false,
    obj_enable: bool = false,
    obj_size: bool = false,
    bg_tile_map: u1 = 0,
    bg_chr_map: bool = false,
    window_enable: bool = false,
    window_tile_map: u1 = 0,
    lcd_enable: bool = false,
};

const Mode = enum(u2) {
    hblank,
    vblank,
    oam_search,
    render,
};

const Status = packed struct(u8) {
    mode: Mode = .oam_search,
    lyc: bool = false,
    int_hblank: bool = false,
    int_vblank: bool = false,
    int_oam: bool = false,
    int_lyc: bool = false,
    __: bool = false,
};
