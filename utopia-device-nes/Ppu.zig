const std = @import("std");
const fw = @import("framework");
const Device = @import("./Device.zig");
const Palette = @import("./Ppu/Palette.zig");
const background = @import("./Ppu/background.zig");

const width = 256;
const height = 240;
const overscan = 8;
const clipped_height = height - 2 * overscan;

const pixel_array_size = width * height * 4;

const dots_per_line = 341;

const pre_render_line = -1;
const vblank_line = 241;
const last_line = 260;

const Self = @This();

ctrl: Control = .{},
mask: Mask = .{},
status: Status = .{},
dot: u32 = 0,
line: i32 = 0,
nmi_active: bool = false,
address: Address = .{},
tmp_address: Address = .{},
fine_x: u3 = 0,
write_toggle: bool = false,
pixels: *[pixel_array_size]u8,
pixel_index: u32 = 0,
bg: background.State = .{},
palette: Palette,

pub fn init(arena: *std.heap.ArenaAllocator) error{OutOfMemory}!Self {
    const pixels = try arena.allocator().alloc(u8, pixel_array_size);

    return .{
        .pixels = pixels[0..pixel_array_size],
        .palette = .init(),
    };
}

pub fn format(self: *const @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("V={d} H={d}", .{ self.line, self.dot });
}

pub fn getVideoState(self: *const Self) fw.VideoState {
    return .{
        .resolution = .{ .x = width, .y = clipped_height },
        .pixel_data = self.pixels[(width * overscan * 4)..][0..(width * clipped_height * 4)],
    };
}

pub fn getDevice(self: *Self) *Device {
    return @alignCast(@fieldParentPtr("ppu", self));
}

pub fn frameDone(self: *const Self) bool {
    return self.pixel_index >= pixel_array_size;
}

pub fn beginFrame(self: *Self) void {
    self.pixel_index = 0;
}

pub fn read(self: *Self, address: u16) u8 {
    return switch (@as(u3, @truncate(address))) {
        2 => blk: {
            // TODO: PPU open bus
            const value: u8 = @bitCast(self.status);
            self.status.vblank = false;
            fw.log.trace("VBlank: {}", .{self.status.vblank});
            self.getDevice().cpu.clearNmi();
            self.write_toggle = false;
            break :blk value;
        },
        else => fw.log.todo("PPU register read: {X:04}", .{address}),
    };
}

pub fn write(self: *Self, address: u16, value: u8) void {
    switch (@as(u3, @truncate(address))) {
        0 => {
            const prev_nmi_output = self.ctrl.nmi_output;
            self.ctrl = @bitCast(value);
            fw.log.debug("PPUCTRL: {any}", .{self.ctrl});

            self.tmp_address.name_table_x = @intFromBool(fw.num.bit(value, 0));
            self.tmp_address.name_table_y = @intFromBool(fw.num.bit(value, 1));
            fw.log.debug("VRAM TMP Address: {X:04}", .{self.tmp_address.get()});

            if (self.ctrl.nmi_output and !prev_nmi_output and self.status.vblank) {
                self.getDevice().cpu.raiseNmi();
            } else {
                self.getDevice().cpu.clearNmi();
            }
        },
        1 => {
            self.mask = @bitCast(value);
            fw.log.debug("PPUMASK: {any}", .{self.mask});
        },
        5 => {
            if (self.write_toggle) {
                self.tmp_address.coarse_y = @truncate(value >> 3);
                self.tmp_address.fine_y = @truncate(value);
                fw.log.debug("VRAM TMP Address: {X:04}", .{self.tmp_address.get()});
            } else {
                self.tmp_address.coarse_x = @truncate(value >> 3);
                self.fine_x = @truncate(value);
                fw.log.debug("VRAM TMP Address: {X:04}", .{self.tmp_address.get()});
            }

            self.write_toggle = !self.write_toggle;
        },
        6 => {
            if (self.write_toggle) {
                self.tmp_address.set((self.tmp_address.get() & 0x7f00) | value);
                self.address = self.tmp_address;
                fw.log.debug("VRAM TMP Address: {X:04}", .{self.tmp_address.get()});
                fw.log.debug("VRAM Address: {X:04}", .{self.address.get()});
                self.getDevice().cartridge.setVramAddress(self.address.get());
            } else {
                self.tmp_address.set((self.tmp_address.get() & 0xff) | (@as(u15, value & 0x3f) << 8));
                fw.log.debug("VRAM TMP Address: {X:04}", .{self.tmp_address.get()});
            }

            self.write_toggle = !self.write_toggle;
        },
        7 => {
            const vram_address = self.address.get();

            fw.log.trace("VRAM Write: {X:04} <= {X:02}", .{ vram_address, value });

            if ((vram_address & 0x3f00) == 0x3f00) {
                self.palette.write(vram_address, value);
            } else {
                self.getDevice().cartridge.writeVram(value);
            }

            self.incrementVramAddress();
        },
        else => fw.log.trace("TODO: PPU register write: {X:04} <= {X:02}", .{ address, value }),
    }
}

pub fn step(self: *Self) void {
    if (self.line < height) {
        @branchHint(.likely);

        if (self.mask.renderEnabled()) {
            @branchHint(.likely);
            self.render();
        } else if (self.dot < 256 and self.line >= 0) {
            self.drawPixel(self.palette.color(0));
        }
    }

    if (self.dot == dots_per_line) {
        @branchHint(.unlikely);
        self.dot = 0;
        self.line += 1;

        if (self.line > last_line) {
            @branchHint(.unlikely);
            self.line = pre_render_line;
            self.status.vblank = false;
            fw.log.trace("VBlank: {}", .{self.status.vblank});
            self.getDevice().cpu.clearNmi();
        } else if (self.line == vblank_line) {
            @branchHint(.unlikely);
            self.status.vblank = true;
            fw.log.trace("VBlank: {}", .{self.status.vblank});

            if (self.ctrl.nmi_output) {
                self.getDevice().cpu.raiseNmi();
            }
        }
    } else {
        self.dot += 1;
    }
}

fn render(self: *Self) void {
    if (self.dot < 256) {
        @branchHint(.likely);

        if (self.line >= 0) {
            @branchHint(.likely);
            self.drawPixel(self.palette.color(0));
        }

        background.loadTiles(self);

        if (self.dot == 255) {
            @branchHint(.unlikely);
            background.incrementScrollY(self);
        }

        return;
    }

    if (self.dot < 320) {
        @branchHint(.likely);

        // TODO: Load object tiles

        if (self.dot == 256) {
            @branchHint(.unlikely);
            background.copyScrollX(self);
        }

        if (self.line == pre_render_line and self.dot >= 279 and self.dot <= 303) {
            @branchHint(.unlikely);
            background.copyScrollY(self);
        }

        return;
    }

    if (self.dot < 336) {
        @branchHint(.likely);
        background.loadTiles(self);
        return;
    }

    if (self.dot < 340) {
        @branchHint(.likely);
        background.loadExtra(self);
        return;
    }
}

fn incrementVramAddress(self: *Self) void {
    const increment: u15 = if (self.ctrl.vram_increment) 32 else 1;
    const result = self.address.get() +% increment;
    self.address.set(result);
    self.getDevice().cartridge.setVramAddress(result);
}

fn drawPixel(self: *Self, color: fw.color.Abgr32) void {
    const pixel: *[4]u8 = self.pixels[self.pixel_index..][0..4];
    pixel.* = @bitCast(color);
    self.pixel_index += 4;
}

const Control = packed struct(u8) {
    __0: u2 = 0,
    vram_increment: bool = false,
    obj_chr_table: u1 = 0,
    bg_chr_table: u1 = 0,
    obj_size: bool = false,
    __1: bool = false,
    nmi_output: bool = false,
};

const Mask = packed struct(u8) {
    greyscale: bool = false,
    bg_show_left: bool = false,
    obj_show_left: bool = false,
    bg_enable: bool = false,
    obj_enable: bool = false,
    emphasis_red: bool = false,
    emphasis_green: bool = false,
    emphasis_blue: bool = false,

    fn renderEnabled(self: @This()) bool {
        return self.bg_enable or self.obj_enable;
    }
};

const Status = packed struct(u8) {
    __: u5 = 0,
    sprite_overflow: bool = false,
    sprite_zero_hit: bool = false,
    vblank: bool = false,
};

const Address = packed struct(u15) {
    coarse_x: u5 = 0,
    coarse_y: u5 = 0,
    name_table_x: u1 = 0,
    name_table_y: u1 = 0,
    fine_y: u3 = 0,

    pub fn get(self: @This()) u15 {
        return @bitCast(self);
    }

    pub fn set(self: *@This(), value: u15) void {
        self.* = @bitCast(value);
    }
};
