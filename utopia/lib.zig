const std = @import("std");
const fw = @import("framework");
const Gb = @import("device-gb");
const N64 = @import("device-n64");
const Nes = @import("device-nes");

pub const log = fw.log;

pub const Device = fw.Device;
pub const InitError = fw.InitError;
pub const Resolution = fw.Resolution;
pub const VideoState = fw.VideoState;
pub const Sample = fw.Sample;
pub const AudioState = fw.AudioState;
pub const ControllerState = fw.ControllerState;
pub const ButtonState = fw.ButtonState;
pub const AxisState = fw.AxisState;

pub const DeviceType = enum {
    gb,
    n64,
    nes,
};

pub const DeviceArgs = union(DeviceType) {
    const Self = @This();

    gb: Gb.Args,
    n64: N64.Args,
    nes: Nes.Args,

    pub fn initDevice(self: Self, allocator: std.mem.Allocator, vfs: anytype) InitError!Device {
        return switch (self) {
            .gb => |device_args| try Gb.init(allocator, vfs, device_args),
            .n64 => |device_args| try N64.init(allocator, vfs, device_args),
            .nes => |device_args| try Nes.init(allocator, vfs, device_args),
        };
    }
};
