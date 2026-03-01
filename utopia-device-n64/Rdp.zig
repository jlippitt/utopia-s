const std = @import("std");
const sdl3 = @import("sdl3");
const fw = @import("framework");
const Device = @import("./Device.zig");
const Core = @import("./Rdp/Core.zig");

const Self = @This();

dma_regs: Dma = .{},
dma_active: Dma = .{},
dma_pending: Dma = .{},
status: Status = .{},
core: Core,

pub fn init(arena: *std.heap.ArenaAllocator) error{ SdlError, OutOfMemory }!Self {
    const core = Core.init(arena) catch |err| {
        switch (err) {
            error.SdlError => fw.log.err("SDL Error: {s}", .{sdl3.errors.get().?}),
            else => {},
        }

        return err;
    };

    return .{
        .core = core,
    };
}

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
    return switch (index) {
        3 => @bitCast(self.status),
        else => fw.log.panic("Unmapped RDP register read: {}", .{index}),
    };
}

pub fn writeRegister(self: *Self, index: u3, value: u32, mask: u32) void {
    switch (index) {
        0 => {
            if (self.status.start_pending) {
                fw.log.todo("DPC_START write while starting pending flag is set", .{});
            }

            fw.num.writeMasked(
                u24,
                &self.dma_regs.start,
                @truncate(value),
                @truncate(mask & ~@as(u32, 7)),
            );

            fw.log.debug("DPC_START: {X:08}", .{self.dma_regs.start});
            self.status.start_pending = true;
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
                fw.log.todo("DPC_END update while start pending flag is not set", .{});
            }

            if (self.dma_active.start != self.dma_active.end and !self.status.freeze) {
                self.transferDma();
            }
        },
        else => fw.log.panic("Unmapped RDP register write: {} <= {X:08}", .{ index, value }),
    }
}

pub fn downloadImageData(self: *Self) void {
    fw.log.pushContext("rdp");
    defer fw.log.popContext();

    self.core.downloadImageData() catch {
        fw.log.panic("SDL Error: {s}", .{sdl3.errors.get().?});
    };
}

pub fn syncFull(self: *Self) void {
    fw.log.pushContext("main");
    defer fw.log.popContext();

    self.status.pipe_busy = false;
    self.status.gclk = false;
    self.getDevice().mi.raiseInterrupt(.dp);
}

fn transferDma(self: *Self) void {
    if (self.status.flush) {
        fw.log.unimplemented("RDP flush flag", .{});
    }

    self.status.pipe_busy = true;
    self.status.gclk = true;

    fw.log.debug("Processing RDP commands..", .{});

    {
        fw.log.pushContext("rdp");
        defer fw.log.popContext();

        if (self.status.xbus) {
            fw.log.todo("RDP XBus DMA", .{});
        } else {
            const rdram = self.getDeviceConst().rdram;

            while (self.dma_active.start != self.dma_active.end) {
                self.core.step(fw.mem.readBe(u64, rdram, self.dma_active.start)) catch {
                    fw.log.panic("SDL Error: {s}", .{sdl3.errors.get().?});
                };

                self.dma_active.start +%= 8;
            }
        }
    }

    // TODO: RDP DMA queue

    fw.log.debug("RDP DMA complete", .{});
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
    cbuf_ready: bool = false,
    dma_busy: bool = false,
    end_pending: bool = false,
    start_pending: bool = false,
    __: u21 = 0,
};

const Dma = struct {
    start: u24 = 0,
    end: u24 = 0,
};
