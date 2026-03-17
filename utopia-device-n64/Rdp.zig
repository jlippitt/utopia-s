const std = @import("std");
const sdl3 = @import("sdl3");
const fw = @import("framework");
const Device = @import("./Device.zig");
const Core = @import("./Rdp/Core.zig");
const register = @import("./register.zig");

pub const InitError = Core.InitError;
pub const RenderError = Core.RenderError;

const Self = @This();

dma_regs: Dma = .{},
dma_active: Dma = .{},
dma_pending: Dma = .{},
status: Status = .{},
clock_reset: u64 = 0,
core: Core,

pub fn init(arena: *std.heap.ArenaAllocator) InitError!Self {
    return .{
        .core = try .init(arena),
    };
}

// External-facing interface

pub fn deinit(self: *Self) void {
    self.core.deinit();
}

pub fn readCommand(self: *Self, address: u32) u32 {
    return self.readRegister(@truncate(address >> 2));
}

pub fn writeCommand(self: *Self, address: u32, value: u32, mask: u32) void {
    self.writeRegister(@truncate(address >> 2), value, mask);
}

pub fn readRegister(self: *Self, index: u3) u32 {
    var sync: bool = true;

    const value: u32 = switch (index) {
        0 => self.dma_regs.start,
        1 => self.dma_regs.end,
        2 => blk: {
            sync = self.status.freeze;
            break :blk self.dma_active.start;
        },
        3 => @bitCast(self.status),
        // TODO: DPC clock (awaiting more accurate timing)
        4 => blk: {
            sync = false;
            break :blk 0x00ff_ffff;
        },
        // 4 => @truncate(
        //     ((self.getDeviceConst().clock.getCycles() - self.clock_reset) / 3) & 0x00ff_ffff,
        // ),
        5 => blk: {
            sync = false;
            break :blk @intFromBool(self.status.cmd_busy);
        },
        6 => @intFromBool(self.status.pipe_busy),
        7 => blk: {
            sync = false;
            break :blk @intFromBool(self.status.tmem_busy);
        },
    };

    if (sync) {
        self.getDevice().rsp.forceSync();
    }

    return value;
}

pub fn writeRegister(self: *Self, index: u3, value: u32, mask: u32) void {
    switch (index) {
        0 => {
            if (!self.status.start_pending) {
                fw.num.writeMasked(
                    u24,
                    &self.dma_regs.start,
                    @truncate(value),
                    @truncate(mask & ~@as(u32, 7)),
                );

                fw.log.debug("DPC_START: {X:08}", .{self.dma_regs.start});
                self.status.start_pending = true;
            }
        },
        1 => {
            fw.num.writeMasked(
                u24,
                &self.dma_regs.end,
                @truncate(value),
                @truncate(mask & ~@as(u32, 7)),
            );

            fw.log.debug("DPC_END: {X:08}", .{self.dma_regs.end});

            if (self.status.start_pending) {
                if (self.dma_active.start == self.dma_active.end) {
                    self.status.start_pending = false;
                    self.dma_active = self.dma_regs;
                    fw.log.debug("RDP DMA Active: {any}", .{self.dma_active});
                } else {
                    fw.log.todo("RDP DMA queue", .{});
                }
            } else {
                self.dma_active.end = self.dma_regs.end;
                fw.log.debug("RDP DMA Active: {any}", .{self.dma_active});
            }

            if (self.dma_active.start != self.dma_active.end and !self.status.freeze) {
                self.transferDma() catch |err| {
                    fw.log.panic("{t}", .{err});
                };
            }
        },
        3 => {
            const masked_value = value & mask;

            register.setFlag(&self.status, "xbus", masked_value, 0);
            register.setFlag(&self.status, "freeze", masked_value, 2);
            register.setFlag(&self.status, "flush", masked_value, 4);

            if (fw.num.bit(masked_value, 6)) {
                self.status.tmem_busy = false;
            }

            if (fw.num.bit(masked_value, 7)) {
                self.status.pipe_busy = false;
            }

            if (fw.num.bit(masked_value, 8)) {
                self.status.cmd_busy = false;
            }

            if (fw.num.bit(masked_value, 9)) {
                self.clock_reset = self.getDeviceConst().clock.getCycles();
                fw.log.debug("DPC_CLOCK reset", .{});
            }

            fw.log.debug("DPC_STATUS: {any}", .{self.status});

            if (self.dma_active.start != self.dma_active.end and !self.status.freeze) {
                self.transferDma() catch |err| {
                    fw.log.panic("{t}", .{err});
                };
            }

            self.getDevice().rsp.forceSync();
        },
        else => fw.log.panic("Unmapped RDP register write: {} <= {X:08}", .{ index, value }),
    }
}

pub fn downloadImageData(self: *Self) RenderError!void {
    fw.log.pushContext("rdp");
    defer fw.log.popContext();
    try self.core.downloadImageData();
}

pub fn transferDma(self: *Self) RenderError!void {
    if (self.status.flush) {
        fw.log.unimplemented("RDP flush flag", .{});
    }

    self.status.pipe_busy = true;
    self.status.gclk = true;

    if (self.status.xbus) {
        fw.log.debug("RDP DMA: Uploading {} commands ({} bytes) from DMEM:{X:03}", .{
            (self.dma_active.end - self.dma_active.start) / 8,
            self.dma_active.end - self.dma_active.start,
            self.dma_active.start & 0xff8,
        });

        fw.log.pushContext("rdp");
        defer fw.log.popContext();

        const dmem = self.getDeviceConst().rsp.getDmemConst();

        while (self.dma_active.start != self.dma_active.end) {
            try self.core.step(fw.mem.readBe(u64, dmem, self.dma_active.start & 0xff8));
            self.dma_active.start +%= 8;
        }
    } else {
        fw.log.debug("RDP DMA: Uploading {} commands ({} bytes) from {X:08}", .{
            (self.dma_active.end - self.dma_active.start) / 8,
            self.dma_active.end - self.dma_active.start,
            self.dma_active.start,
        });

        const rdram = self.getDeviceConst().rdram;

        fw.log.pushContext("rdp");
        defer fw.log.popContext();

        while (self.dma_active.start != self.dma_active.end) {
            try self.core.step(fw.mem.readBe(u64, rdram, self.dma_active.start));
            self.dma_active.start +%= 8;
        }
    }

    // TODO: RDP DMA queue
}

// Internal-facing interface

pub fn syncFull(self: *Self) void {
    fw.log.pushContext("main");
    defer fw.log.popContext();

    self.status.pipe_busy = false;
    self.status.gclk = false;
    self.getDevice().mi.raiseInterrupt(.dp);
    self.getDevice().rsp.forceSync();
}

pub fn getDevice(self: *Self) *Device {
    return @alignCast(@fieldParentPtr("rdp", self));
}

pub fn getDeviceConst(self: *const Self) *const Device {
    return @alignCast(@fieldParentPtr("rdp", self));
}

const Status = packed struct(u32) {
    xbus: bool = false,
    freeze: bool = false,
    flush: bool = false,
    gclk: bool = false,
    tmem_busy: bool = false,
    pipe_busy: bool = false,
    cmd_busy: bool = false,
    cbuf_ready: bool = true,
    dma_busy: bool = false,
    end_pending: bool = false,
    start_pending: bool = false,
    __: u21 = 0,
};

const Dma = struct {
    start: u24 = 0,
    end: u24 = 0,
};
