const std = @import("std");
const Device = @import("./Device.zig");
const fw = @import("framework");

const pif_size = 0x800;
const pif_ram_begin = 0x7c0;
const pif_ram_size = pif_size - pif_ram_begin;
const cmd_byte = 0x7ff;

const Self = @This();

pifdata: *align(4) [pif_size]u8,
pif_rom_locked: bool = false,
dram_addr: u24 = 0,
status: Status = .{},
controller_state: [4]u8 = @splat(0),
joybus_program: [64]u8 = @splat(0),

pub fn init(pifdata: []align(4) u8, cic_seed: u32) Self {
    // Command byte should be zero at reset
    pifdata[cmd_byte] = 0;

    // CIC seed should be present at reset
    fw.mem.writeBe(u32, pifdata, 0x7e4, cic_seed);

    return .{
        .pifdata = pifdata[0..pif_size],
    };
}

pub fn read(self: *Self, address: u32) u32 {
    return switch (@as(u4, @truncate(address >> 2))) {
        0 => self.dram_addr,
        6 => blk: {
            self.status.interrupt = self.getDeviceConst().mi.hasInterrupt(.si);
            break :blk @bitCast(self.status);
        },
        else => fw.log.panic("Unmapped SI register read: {X:08}", .{address}),
    };
}

pub fn write(self: *Self, address: u32, value: u32, mask: u32) void {
    switch (@as(u4, @truncate(address >> 2))) {
        0 => {
            fw.num.writeMasked(u24, &self.dram_addr, @truncate(value), @truncate(mask));
            fw.log.debug("  SI_DRAM_ADDR: {X:08}", .{self.dram_addr});
        },
        1 => self.transferDma(.read, @truncate(value & mask & 0x7fc)),
        4 => self.transferDma(.write, @truncate(value & mask & 0x7fc)),
        6 => self.getDevice().mi.clearInterrupt(.si),
        else => fw.log.panic("Unmapped SI register write: {X:08} <= {X:08}", .{ address, value }),
    }
}

pub fn readPif(self: *Self, address: u32) u32 {
    const index: u32 = address & 0x000f_fffc;

    if (index < pif_ram_begin and self.pif_rom_locked) {
        @branchHint(.unlikely);
        fw.log.warn("Read from locked PIF ROM area: {X:08}", .{address});
        return 0;
    }

    if (index >= pif_size) {
        @branchHint(.unlikely);
        fw.log.warn("PIF read out of range: {X:08}", .{address});
        return 0;
    }

    return fw.mem.readBe(u32, self.pifdata, index);
}

pub fn writePif(self: *Self, address: u32, value: u32, mask: u32) void {
    const index: u32 = address & 0x000f_fffc;

    if (index < pif_ram_begin) {
        @branchHint(.unlikely);
        fw.log.warn("Write to PIF ROM area: {X:08} <= {X:08}", .{ address, value });
        return;
    }

    if (index >= pif_size) {
        @branchHint(.unlikely);
        fw.log.warn("PIF write out of range: {X:08} <= {X:08}", .{ address, value });
        return;
    }

    fw.mem.writeMaskedBe(u32, self.pifdata, index, value, mask);

    self.processPifCommand();

    self.getDevice().mi.raiseInterrupt(.si);
}

pub fn updateControllerState(self: *Self, new_state: *const fw.ControllerState) void {
    const axis = &new_state.axis;
    const button = &new_state.button;
    const state = &self.controller_state;

    state[0] = 0;
    state[0] |= if (button.south) 0x80 else 0; // A
    state[0] |= if (button.west) 0x40 else 0; // A
    state[0] |= if (button.left_shoulder) 0x20 else 0; // Z
    state[0] |= if (button.start) 0x10 else 0; // Start
    state[0] |= if (button.dpad_up) 0x08 else 0; // D-Pad Up
    state[0] |= if (button.dpad_down) 0x04 else 0; // D-Pad Down
    state[0] |= if (button.dpad_left) 0x02 else 0; // D-Pad Left
    state[0] |= if (button.dpad_right) 0x01 else 0; // D-Pad Right

    state[1] = 0;
    state[1] |= if (axis.left_trigger >= 0.5) 0x20 else 0; // L
    state[1] |= if (axis.right_trigger >= 0.5 or button.right_shoulder) 0x10 else 0; // R
    state[1] |= if (axis.right_y <= -0.75) 0x08 else 0; // C Up
    state[1] |= if (axis.right_y >= 0.75 or button.east) 0x04 else 0; // C Down
    state[1] |= if (axis.right_x <= -0.75 or button.north) 0x02 else 0; // C Left
    state[1] |= if (axis.right_x >= 0.75) 0x01 else 0; // C Right

    const left_x = axis.left_x * (83.0 - @abs(axis.left_y) * 17.0);
    const left_y = axis.left_y * (83.0 - @abs(axis.left_x) * 17.0);

    state[2] = @bitCast(@as(i8, @intFromFloat(left_x)));
    state[3] = @bitCast(@as(i8, @intFromFloat(-left_y)));
}

fn transferDma(self: *Self, comptime direction: DmaDirection, pif_addr: u11) void {
    const len = pif_ram_size;

    if ((self.dram_addr & 7) != 0) {
        fw.log.unimplemented("SI DMA with misaligned DRAM address: {X:08}", .{
            self.dram_addr,
        });
    }

    if (pif_addr != pif_ram_begin) {
        fw.log.unimplemented("SI DMA with non-PIF RAM address: {X:03}", .{
            pif_addr,
        });
    }

    switch (comptime direction) {
        .read => {
            self.executeJoybusProgram();

            const rdram = self.getDevice().rdram;

            @memcpy(rdram[self.dram_addr..][0..len], self.pifdata[pif_addr..][0..len]);

            fw.log.debug("SI DMA: {} bytes read from PIF:{X:03} to {X:08}", .{
                len,
                pif_addr,
                self.dram_addr,
            });
        },
        .write => {
            const rdram = self.getDeviceConst().rdram;

            @memcpy(self.pifdata[pif_addr..][0..len], rdram[self.dram_addr..][0..len]);

            fw.log.debug("SI DMA: {} bytes written from {X:08} to PIF:{X:03}", .{
                len,
                self.dram_addr,
                pif_addr,
            });

            self.processPifCommand();
        },
    }

    self.dram_addr +%= len;

    self.getDevice().mi.raiseInterrupt(.si);
}

fn getDevice(self: *Self) *Device {
    return @alignCast(@fieldParentPtr("si", self));
}

fn getDeviceConst(self: *Self) *const Device {
    return @alignCast(@fieldParentPtr("si", self));
}

fn processPifCommand(self: *Self) void {
    const cmd = self.pifdata[cmd_byte];

    if ((cmd & 0x7f) == 0) {
        return;
    }

    var result: u8 = 0;

    if ((cmd & 0x01) != 0) {
        @memcpy(&self.joybus_program, self.pifdata[pif_ram_begin..]);
        fw.log.trace("Joybus configured", .{});
    }

    if ((cmd & 0x02) != 0) {
        fw.log.todo("PIF challenge/response", .{});
    }

    if ((cmd & 0x10) != 0) {
        self.pif_rom_locked = true;
        fw.log.trace("PIF ROM Locked: {}", .{self.pif_rom_locked});
    }

    if ((cmd & 0x20) != 0) {
        fw.log.trace("PIF Acquire Checksum", .{});
        result |= 0x80;
    }

    self.pifdata[cmd_byte] = result;
}

fn executeJoybusProgram(self: *Self) void {
    fw.log.debug("PIF Joybus Input: {any}", .{self.joybus_program});

    const pif_ram = self.pifdata[pif_ram_begin..][0..pif_ram_size];

    var channel: u32 = 0;
    var index: u32 = 0;

    while (index < (pif_ram_size - 1)) {
        const send_len: u32 = self.joybus_program[index];
        index += 1;

        if (send_len == 0xfe) {
            break;
        }

        if ((send_len & 0xc0) != 0) {
            continue;
        }

        if (send_len == 0) {
            channel += 1;
            continue;
        }

        const recv_len: u32 = self.joybus_program[index];
        index += 1;

        if (recv_len == 0xfe) {
            break;
        }

        if ((index + send_len) > pif_ram_size) {
            fw.log.warn("Joybus send length too large", .{});
            break;
        }

        const send_data = self.joybus_program[index..][0..send_len];
        index += send_len;

        if ((index + recv_len) > pif_ram_size) {
            fw.log.warn("Joybus receive length too large", .{});
            break;
        }

        const recv_data = self.queryJoybus(channel, pif_ram[index..], send_data) catch {
            fw.log.warn("Joybus output too large", .{});
            break;
        };

        if (recv_data.len == 0) {
            pif_ram[index - 2] |= 0x80;
        } else {
            if (recv_data.len != recv_len) {
                fw.log.warn("Joybus output does not match expected length: {} (expected {})", .{
                    recv_data.len,
                    recv_len,
                });
            }

            index += recv_len;
        }

        channel += 1;
    }

    fw.log.debug("PIF Joybus Input: {any}", .{pif_ram});
}

fn queryJoybus(
    self: *Self,
    channel: u32,
    recv_buf: []u8,
    send_data: []const u8,
) error{OutOfMemory}![]const u8 {
    var recv_data = std.ArrayListUnmanaged(u8).initBuffer(recv_buf);

    switch (send_data[0]) {
        0x00, 0xff => {
            fw.log.debug("Joybus Query: Info ({})", .{channel});

            switch (channel) {
                0 => {
                    // TODO: Controller pak
                    try recv_data.appendSliceBounded(&.{ 0x05, 0x00, 0x02 });
                },
                1, 2, 3 => {}, // TODO: Multiple controller support
                4 => fw.log.todo("EEPROM", .{}),
                else => fw.log.panic("Invalid joybus channel: {}", .{channel}),
            }
        },
        0x01 => {
            fw.log.debug("Joybus Query: Controller State ({})", .{channel});

            switch (channel) {
                0 => try recv_data.appendSliceBounded(&self.controller_state),
                1, 2, 3 => {}, // TODO: Multiple controller support
                else => fw.log.panic("Invalid joybus channel: {}", .{channel}),
            }
        },
        0x03 => {
            fw.log.debug("Joybus Query: Write Controller Accessor ({})", .{channel});

            if (channel >= 4) {
                fw.log.panic("Invalid joybus channel: {}", .{channel});
            }

            try recv_data.appendBounded(crc8(send_data[3..35]));
        },
        else => |cmd| fw.log.unimplemented("Joybus command: {X:02}", .{cmd}),
    }

    return recv_data.items;
}

fn crc8(data: []const u8) u8 {
    var result: u8 = 0;

    for (data, 0..) |byte, index| {
        for (0..8) |bit| {
            const xor_tap: u8 = if ((result & 0x80) != 0) 0x85 else 0;

            result <<= 1;

            if (index < data.len and (byte & (@as(u8, 0x80) >> @intCast(bit))) != 0) {
                result |= 1;
            }

            result ^= xor_tap;
        }
    }

    return result;
}

const Status = packed struct(u32) {
    dma_busy: bool = false,
    io_busy: bool = false,
    read_pending: bool = false,
    dma_error: bool = false,
    pch_state: u4 = 0,
    dma_state: u4 = 0,
    interrupt: bool = false,
    __: u19 = 0,
};

const DmaDirection = enum {
    read,
    write,
};
