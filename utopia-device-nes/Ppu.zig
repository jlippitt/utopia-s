const std = @import("std");
const fw = @import("framework");
const Device = @import("./Device.zig");

const dots_per_line = 341;

const pre_render_line = -1;
const vblank_line = 241;
const last_line = 260;

const Self = @This();

ctrl: Control = .{},
status: Status = .{},
dot: u32 = 0,
line: i32 = 0,
nmi_active: bool = false,
address: Address = .{},
tmp_address: Address = .{},
fine_x: u3 = 0,
write_toggle: bool = false,

pub fn init() Self {
    return .{};
}

pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("V={d} H={d}", .{ self.line, self.dot });
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

            self.address.name_table_x = fw.num.bit(value, 0);
            self.address.name_table_y = fw.num.bit(value, 1);
            fw.log.debug("VRAM Address: {X:04}", .{self.address.get()});

            if (self.ctrl.nmi_output and !prev_nmi_output and self.status.vblank) {
                self.getDevice().cpu.raiseNmi();
            } else {
                self.getDevice().cpu.clearNmi();
            }
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
            } else {
                self.tmp_address.set((self.tmp_address.get() & 0xff) | (@as(u15, value & 0x3f) << 8));
                fw.log.debug("VRAM TMP Address: {X:04}", .{self.tmp_address.get()});
            }

            self.write_toggle = !self.write_toggle;
        },
        else => fw.log.trace("TODO: PPU register write: {X:04} <= {X:02}", .{ address, value }),
    }
}

pub fn step(self: *Self) void {
    if (self.dot == dots_per_line) {
        @branchHint(.unlikely);
        self.dot = 0;
        self.line += 1;

        if (self.line > last_line) {
            self.line = pre_render_line;
            self.status.vblank = false;
            fw.log.trace("VBlank: {}", .{self.status.vblank});
            self.getDevice().cpu.clearNmi();
        } else if (self.line == vblank_line) {
            self.status.vblank = true;
            fw.log.trace("VBlank: {}", .{self.status.vblank});

            if (self.ctrl.nmi_output) {
                self.getDevice().cpu.raiseNmi();
            }
        }
    }

    self.dot += 1;
}

fn getDevice(self: *Self) *Device {
    return @alignCast(@fieldParentPtr("ppu", self));
}

const Control = packed struct(u8) {
    __0: u2 = 0,
    vram_increment: bool = false,
    obj_chr_table: bool = false,
    bg_chr_table: bool = false,
    obj_size: bool = false,
    __1: bool = false,
    nmi_output: bool = false,
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
    name_table_x: bool = false,
    name_table_y: bool = false,
    fine_y: u3 = 0,

    pub fn get(self: @This()) u15 {
        return @bitCast(self);
    }

    pub fn set(self: *@This(), value: u15) void {
        self.* = @bitCast(value);
    }
};
