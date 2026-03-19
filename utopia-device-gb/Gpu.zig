const fw = @import("framework");

const Self = @This();

ctrl: Control = .{},
status: Status = .{},
scroll_y: u8 = 0,
scroll_x: u8 = 0,
bg_palette: u8 = 0,
obj_palette: [2]u8 = @splat(0),

pub fn init() Self {
    return .{};
}

pub fn read(self: *Self, address: u8) u8 {
    return switch (address) {
        0x40 => @bitCast(self.ctrl),
        0x41 => @bitCast(self.status),
        0x42 => self.scroll_y,
        0x43 => self.scroll_x,
        0x44 => 0x90,
        0x47 => self.bg_palette,
        0x48 => self.obj_palette[0],
        0x49 => self.obj_palette[1],
        else => fw.log.todo("GPU register read: {X:02}", .{address}),
    };
}

pub fn write(self: *Self, address: u8, value: u8) void {
    switch (address) {
        0x40 => {
            self.ctrl = @bitCast(value);
            fw.log.debug("LCD Control: {any}", .{self.ctrl});
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
        else => fw.log.todo("GPU register write: {X:02}", .{address}),
    }
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
    mode: Mode = .hblank,
    lyc: bool = false,
    int_hblank: bool = false,
    int_vblank: bool = false,
    int_oam: bool = false,
    int_lyc: bool = false,
    __: bool = false,
};
