const std = @import("std");
const fw = @import("framework");
const N64 = @import("device-n64");

pub const DefaultArgs = fw.DefaultArgs;

pub const DeviceType = enum {
    n64,
};

pub const DeviceArgs = union(DeviceType) {
    n64: N64.Args,
};

pub const Device = struct {
    const Self = @This();

    inner: fw.Device,

    pub fn init(args: DefaultArgs, device_args: DeviceArgs) !Self {
        const inner = switch (device_args) {
            .n64 => |n64_args| try N64.init(args, n64_args),
        };

        return .{
            .inner = inner,
        };
    }

    pub fn deinit(self: *Self) void {
        self.inner.deinit();
    }

    pub fn runFrame(self: *Self) void {
        self.inner.runFrame();
    }
};
