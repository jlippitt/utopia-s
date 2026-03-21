const std = @import("std");

pub const color = @import("./color.zig");
pub const fs = @import("./fs.zig");
pub const log = @import("./log.zig");
pub const lru = @import("./lru.zig");
pub const mem = @import("./mem.zig");
pub const num = @import("./num.zig");
pub const processor = @import("./processor.zig");

pub const default_sample_rate = 48000;

pub const CliArg = struct {
    short_name: ?u8,
    desc: []const u8,
};

pub const InitError = std.mem.Allocator.Error ||
    std.fs.File.OpenError ||
    std.fs.File.ReadError ||
    error{
        ArgError,
        SdlError,
    };

pub const Resolution = struct {
    x: u32,
    y: u32,
};

pub const VideoState = struct {
    resolution: Resolution,
    pixel_data: []const u8,
};

pub const Sample = [2]i16;

pub const AudioState = struct {
    sample_rate: u32,
    sample_data: []const Sample,
};

pub const ControllerState = struct {
    axis: AxisState = .{},
    button: ButtonState = .{},
};

/// These match SDL axis names
pub const AxisState = struct {
    left_x: f32 = 0.0,
    left_y: f32 = 0.0,
    right_x: f32 = 0.0,
    right_y: f32 = 0.0,
    left_trigger: f32 = 0.0,
    right_trigger: f32 = 0.0,
};

/// These match SDL button names
pub const ButtonState = struct {
    south: bool = false,
    east: bool = false,
    west: bool = false,
    north: bool = false,
    select: bool = false,
    back: bool = false,
    guide: bool = false,
    start: bool = false,
    left_stick: bool = false,
    right_stick: bool = false,
    left_shoulder: bool = false,
    right_shoulder: bool = false,
    dpad_up: bool = false,
    dpad_down: bool = false,
    dpad_left: bool = false,
    dpad_right: bool = false,
    misc1: bool = false,
    right_paddle1: bool = false,
    left_paddle1: bool = false,
    right_paddle2: bool = false,
    left_paddle2: bool = false,
    touchpad: bool = false,
    misc2: bool = false,
    misc3: bool = false,
    misc4: bool = false,
    misc5: bool = false,
    misc6: bool = false,
};

pub fn Interface(comptime Self: type) type {
    return struct {
        deinit: *const fn (self: *Self) void,
        runFrame: *const fn (self: *Self) void,
        getVideoState: *const fn (self: *const Self) VideoState,
        getAudioState: *const fn (self: *const Self) AudioState,
        updateControllerState: *const fn (self: *Self, state: *const ControllerState) void,
    };
}

pub const Device = struct {
    const Self = @This();

    ptr: *anyopaque,
    vtable: *const Interface(anyopaque),

    pub fn init(
        inner: anytype,
        comptime iface: Interface(@typeInfo(@TypeOf(inner)).pointer.child),
    ) InitError!Self {
        const Inner = @typeInfo(@TypeOf(inner)).pointer.child;

        const gen = struct {
            fn deinitImpl(ptr: *anyopaque) void {
                const self: *Inner = @ptrCast(@alignCast(ptr));
                return @call(.always_inline, iface.deinit, .{self});
            }

            fn runFrameImpl(ptr: *anyopaque) void {
                const self: *Inner = @ptrCast(@alignCast(ptr));
                return @call(.always_inline, iface.runFrame, .{self});
            }

            fn getVideoStateImpl(ptr: *const anyopaque) VideoState {
                const self: *const Inner = @ptrCast(@alignCast(ptr));
                return @call(.always_inline, iface.getVideoState, .{self});
            }

            fn getAudioStateImpl(ptr: *const anyopaque) AudioState {
                const self: *const Inner = @ptrCast(@alignCast(ptr));
                return @call(.always_inline, iface.getAudioState, .{self});
            }

            fn updateControllerStateImpl(ptr: *anyopaque, state: *const ControllerState) void {
                const self: *Inner = @ptrCast(@alignCast(ptr));
                return @call(.always_inline, iface.updateControllerState, .{ self, state });
            }

            const vtable = Interface(anyopaque){
                .deinit = deinitImpl,
                .runFrame = runFrameImpl,
                .getVideoState = getVideoStateImpl,
                .getAudioState = getAudioStateImpl,
                .updateControllerState = updateControllerStateImpl,
            };
        };

        return .{
            .ptr = inner,
            .vtable = &gen.vtable,
        };
    }

    pub fn deinit(self: Self) void {
        return self.vtable.deinit(self.ptr);
    }

    pub fn runFrame(self: Self) void {
        return self.vtable.runFrame(self.ptr);
    }

    pub fn getVideoState(self: Self) VideoState {
        return self.vtable.getVideoState(self.ptr);
    }

    pub fn getAudioState(self: Self) AudioState {
        return self.vtable.getAudioState(self.ptr);
    }

    pub fn updateControllerState(self: *Self, state: *const ControllerState) void {
        return self.vtable.updateControllerState(self.ptr, state);
    }
};
