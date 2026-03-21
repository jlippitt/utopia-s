const std = @import("std");
const fw = @import("framework");
const Device = @import("../Device.zig");
const Apu = @import("../Apu.zig");

const frame_timings: std.enums.EnumArray(Mode, [6]u32) = .init(.{
    .step4 = .{ 7457, 7456, 7458, 7457, 1, 1 },
    .step5 = .{ 7457, 7456, 7458, 7458, 7452, 1 },
});

pub const Frame = enum(u1) {
    quarter,
    half,
};

const Self = @This();

ctrl: Control = .{},
frame_number: u32 = 0,
cycles_remaining: u32 = frame_timings.get(.step4)[0],
delay_cycles: u32 = 0,

pub fn init() Self {
    return .{};
}

pub fn setControl(self: *Self, value: u8) void {
    self.ctrl = @bitCast(value);
    fw.log.debug("Frame Counter Control: {any}", .{self.ctrl});

    if (self.ctrl.irq_inhibit) {
        self.getDevice().irq.clear(.frame_counter);
    }

    self.delay_cycles = 2 - @as(u32, @intCast(self.getDevice().cycles & 1));
}

pub fn step(self: *Self) ?Frame {
    if (self.delay_cycles > 0) {
        @branchHint(.unlikely);
        self.delay_cycles -= 1;

        if (self.delay_cycles == 0) {
            self.frame_number = 0;
            self.cycles_remaining = frame_timings.get(self.ctrl.mode)[0] + 2;

            fw.log.debug("Frame Counter Step: {} (Cycles Remaining: {})", .{
                self.frame_number,
                self.cycles_remaining,
            });

            return if (self.ctrl.mode == .step5) .half else null;
        }
    }

    self.cycles_remaining -= 1;

    if (self.cycles_remaining > 0) {
        @branchHint(.likely);
        return null;
    }

    const event: ?Frame = switch (self.frame_number) {
        0 => blk: {
            self.frame_number = 1;
            break :blk .quarter;
        },
        1 => blk: {
            self.frame_number = 2;
            break :blk .half;
        },
        2 => blk: {
            self.frame_number = 3;
            break :blk .quarter;
        },
        3 => blk: {
            if (self.ctrl.mode == .step4 and !self.ctrl.irq_inhibit) {
                self.getDevice().irq.raise(.frame_counter);
            }

            self.frame_number = 4;
            break :blk null;
        },
        4 => blk: {
            if (self.ctrl.mode == .step4 and !self.ctrl.irq_inhibit) {
                self.getDevice().irq.raise(.frame_counter);
            }

            self.frame_number = 5;
            break :blk .half;
        },
        5 => blk: {
            if (self.ctrl.mode == .step4 and !self.ctrl.irq_inhibit) {
                self.getDevice().irq.raise(.frame_counter);
            }

            self.frame_number = 0;
            break :blk null;
        },
        else => unreachable,
    };

    self.cycles_remaining = frame_timings.get(self.ctrl.mode)[self.frame_number];

    fw.log.debug("Frame Counter Step: {} (Cycles Remaining: {})", .{
        self.frame_number,
        self.cycles_remaining,
    });

    return event;
}

fn getApu(self: *Self) *Apu {
    return @alignCast(@fieldParentPtr("frame_counter", self));
}

fn getDevice(self: *Self) *Device {
    return self.getApu().getDevice();
}

const Mode = enum(u1) {
    step4,
    step5,
};

const Control = packed struct(u8) {
    __: u6 = 0,
    irq_inhibit: bool = false,
    mode: Mode = .step4,
};
