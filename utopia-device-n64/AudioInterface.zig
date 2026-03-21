const std = @import("std");
const fw = @import("framework");
const Device = @import("./Device.zig");
const Clock = @import("./Clock.zig");

const max_sample_rate = fw.default_sample_rate;

// Allow for 2 frames worth of data
const sample_buffer_size = max_sample_rate * 2;

const Self = @This();

dram_addr: u24 = 0,
dma_enable: bool = false,
status: Status = .{},
dacrate: u14 = 0,
bitrate: u4 = 0,
sample_rate: u32,
cycles_per_sample: u64,
dma_active: Dma = .{},
dma_pending: Dma = .{},
sample_buffer: std.ArrayList(fw.Sample),

pub fn init(arena: *std.heap.ArenaAllocator, clock: *Clock) error{OutOfMemory}!Self {
    const sample_buffer = try std.ArrayList(fw.Sample).initCapacity(
        arena.allocator(),
        sample_buffer_size,
    );

    const sample_rate, const cycles_per_sample = calcSampleRates(0);
    fw.log.debug("Sample Rate: {}", .{sample_rate});
    fw.log.debug("Cycles Per Sample: {}", .{cycles_per_sample});
    clock.schedule(.ai_sample, cycles_per_sample);

    return .{
        .sample_buffer = sample_buffer,
        .sample_rate = sample_rate,
        .cycles_per_sample = cycles_per_sample,
    };
}

pub fn getAudioState(self: *const Self) fw.AudioState {
    return .{
        .sample_rate = self.sample_rate,
        .sample_data = self.sample_buffer.items,
    };
}

pub fn clearSampleBuffer(self: *Self) void {
    self.sample_buffer.clearRetainingCapacity();
}

pub fn read(self: *Self, address: u32) u32 {
    return switch (@as(u3, @truncate(address >> 2))) {
        0, 1, 2, 4, 5 => self.dma_active.len,
        3 => blk: {
            const busy = self.dma_active.len != 0;
            const full = busy and self.dma_pending.len != 0;

            self.status.full_0 = full;
            self.status.enabled = self.dma_enable;
            self.status.busy = busy;
            self.status.full_31 = full;

            break :blk @bitCast(self.status);
        },
        else => fw.log.panic("Unmapped AI register read: {X:08}", .{address}),
    };
}

pub fn write(self: *Self, address: u32, value: u32, mask: u32) void {
    switch (@as(u3, @truncate(address >> 2))) {
        0 => {
            fw.num.writeMasked(
                u24,
                &self.dram_addr,
                @truncate(value),
                @truncate(mask & ~@as(u32, 7)),
            );

            fw.log.debug("AI_DRAM_ADDR: {X:08}", .{self.dram_addr});
        },
        1 => {
            const len: u18 = @truncate(value & mask & ~@as(u32, 7));

            if (len != 0) {
                const dma: Dma = .{
                    .dram_addr = self.dram_addr,
                    .len = len,
                };

                if (self.dma_active.len == 0) {
                    self.dma_active = dma;
                    fw.log.debug("AI DMA Active: {any}", .{self.dma_active});
                    self.getDevice().mi.raiseInterrupt(.ai);
                } else if (self.dma_pending.len == 0) {
                    self.dma_pending = dma;
                    fw.log.debug("AI DMA Pending: {any}", .{self.dma_pending});
                } else {
                    fw.log.panic("AI DMA queue full", .{});
                }
            }
        },
        2 => {
            fw.num.writeMasked(
                u1,
                @ptrCast(&self.dma_enable),
                @truncate(value),
                @truncate(mask),
            );

            fw.log.debug("AI_CONTROL (Dma Enable): {}", .{self.dma_enable});
        },
        3 => self.getDevice().mi.clearInterrupt(.ai),
        4 => {
            fw.num.writeMasked(
                u14,
                &self.dacrate,
                @truncate(value),
                @truncate(mask),
            );

            fw.log.debug("AI_DACRATE: {}", .{self.dacrate});

            const prev_cycles_per_sample = self.cycles_per_sample;
            const sample_rate, const cycles_per_sample = calcSampleRates(self.dacrate);

            self.sample_rate = sample_rate;
            fw.log.debug("Sample Rate: {}", .{self.sample_rate});
            self.cycles_per_sample = cycles_per_sample;
            fw.log.debug("Cycles Per Sample: {}", .{self.cycles_per_sample});

            if (self.cycles_per_sample != prev_cycles_per_sample) {
                self.getDevice().clock.reschedule(.ai_sample, self.cycles_per_sample);
            }
        },
        5 => {
            fw.num.writeMasked(
                u4,
                &self.bitrate,
                @truncate(value),
                @truncate(mask),
            );

            fw.log.debug("AI_BITRATE: {}", .{self.bitrate});
        },
        else => fw.log.panic("Unmapped AI register write: {X:08} <= {X:08}", .{ address, value }),
    }
}

pub fn handleSampleEvent(self: *Self) void {
    if (self.dma_enable and self.dma_active.len != 0) {
        const rdram = self.getDeviceConst().rdram;

        const left = fw.mem.readBe(i16, rdram, self.dma_active.dram_addr);
        const right = fw.mem.readBe(i16, rdram, self.dma_active.dram_addr +% 2);

        self.sample_buffer.appendAssumeCapacity(.{
            @as(f32, @floatFromInt(left)) / 32768.0,
            @as(f32, @floatFromInt(right)) / 32768.0,
        });

        self.dma_active.dram_addr +%= 4;
        self.dma_active.len -= 4;

        if (self.dma_active.len == 0) {
            self.dma_active = self.dma_pending;
            self.dma_pending = .{};

            if (self.dma_active.len != 0) {
                fw.log.debug("AI DMA Active: {any}", .{self.dma_active});
                self.getDevice().mi.raiseInterrupt(.ai);
            } else {
                fw.log.debug("AI DMA Complete", .{});
            }
        }
    } else {
        self.sample_buffer.appendAssumeCapacity(.{ 0.0, 0.0 });
    }

    self.getDevice().clock.schedule(.ai_sample, self.cycles_per_sample);
}

fn getDevice(self: *Self) *Device {
    return @alignCast(@fieldParentPtr("ai", self));
}

fn getDeviceConst(self: *const Self) *const Device {
    return @alignCast(@fieldParentPtr("ai", self));
}

fn calcSampleRates(dacrate: u14) struct { u32, u64 } {
    const sample_rate = @min(
        Device.video_dac_rate / (@as(f64, @floatFromInt(dacrate)) + 1.0),
        max_sample_rate,
    );

    const cycles_per_sample = Device.clock_rate / sample_rate;

    return .{
        @intFromFloat(sample_rate),
        @intFromFloat(cycles_per_sample),
    };
}

const Status = packed struct(u32) {
    full_0: bool = false,
    count: u14 = 0,
    __0: u1 = 0,
    bc: bool = false,
    __1: u2 = 0,
    wc: bool = false,
    __2: u5 = 0b10001,
    enabled: bool = false,
    __3: u4 = 0,
    busy: bool = false,
    full_31: bool = false,
};

const Dma = struct {
    dram_addr: u24 = 0,
    len: u18 = 0,
};
