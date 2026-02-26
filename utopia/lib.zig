const std = @import("std");
const fw = @import("framework");
const N64 = @import("device-n64");

pub const log = struct {
    pub const Level = fw.log.Level;
    pub const Interface = fw.log.Interface;
};

pub const Device = fw.Device;
pub const DeviceError = fw.DeviceError;
pub const ScreenSize = fw.ScreenSize;

pub const DeviceType = enum {
    n64,
};

pub const DeviceArgs = union(DeviceType) {
    const Self = @This();

    n64: N64.Args,

    pub fn initDevice(self: Self, allocator: std.mem.Allocator) DeviceError!Device {
        return switch (self) {
            .n64 => |device_args| try N64.init(allocator, device_args),
        };
    }
};
