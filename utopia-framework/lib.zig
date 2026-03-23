const std = @import("std");

pub const color = @import("./color.zig");
pub const log = @import("./log.zig");
pub const lru = @import("./lru.zig");
pub const mem = @import("./mem.zig");
pub const num = @import("./num.zig");

pub const default_sample_rate = 48000;

pub const CliArg = struct {
    short_name: ?u8,
    desc: []const u8,
};

pub const InitError = Vfs.Error || error{
    ArgError,
    SdlError,
};

pub const Resolution = struct {
    x: u32,
    y: u32,
};

pub const ScaleMode = enum(u1) {
    integer,
    float,
};

pub const VideoState = struct {
    resolution: Resolution,
    scale_mode: ScaleMode,
    pixel_data: []const u8,
};

pub const Sample = [2]f32;

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

pub const Device = struct {
    pub fn Interface(comptime T: type) type {
        return struct {
            deinit: *const fn (self: *T) void,
            runFrame: *const fn (self: *T) void,
            getVideoState: *const fn (self: *const T) VideoState,
            getAudioState: *const fn (self: *const T) AudioState,
            updateControllerState: *const fn (self: *T, state: *const ControllerState) void,
            save: *const fn (self: *T, allocator: std.mem.Allocator, vfs: Vfs) Vfs.Error!void,
        };
    }

    const Self = @This();

    ptr: *anyopaque,
    vtable: *const Interface(anyopaque),

    pub fn init(
        inner: anytype,
        comptime iface: Interface(@typeInfo(@TypeOf(inner)).pointer.child),
    ) Self {
        const T = @typeInfo(@TypeOf(inner)).pointer.child;

        const gen = struct {
            fn deinitImpl(ptr: *anyopaque) void {
                const self: *T = @ptrCast(@alignCast(ptr));
                return @call(.always_inline, iface.deinit, .{self});
            }

            fn runFrameImpl(ptr: *anyopaque) void {
                const self: *T = @ptrCast(@alignCast(ptr));
                return @call(.always_inline, iface.runFrame, .{self});
            }

            fn getVideoStateImpl(ptr: *const anyopaque) VideoState {
                const self: *const T = @ptrCast(@alignCast(ptr));
                return @call(.always_inline, iface.getVideoState, .{self});
            }

            fn getAudioStateImpl(ptr: *const anyopaque) AudioState {
                const self: *const T = @ptrCast(@alignCast(ptr));
                return @call(.always_inline, iface.getAudioState, .{self});
            }

            fn updateControllerStateImpl(ptr: *anyopaque, state: *const ControllerState) void {
                const self: *T = @ptrCast(@alignCast(ptr));
                return @call(.always_inline, iface.updateControllerState, .{ self, state });
            }

            fn saveImpl(ptr: *anyopaque, allocator: std.mem.Allocator, vfs: Vfs) Vfs.Error!void {
                const self: *T = @ptrCast(@alignCast(ptr));
                return @call(.always_inline, iface.save, .{ self, allocator, vfs });
            }

            const vtable = Interface(anyopaque){
                .deinit = deinitImpl,
                .runFrame = runFrameImpl,
                .getVideoState = getVideoStateImpl,
                .getAudioState = getAudioStateImpl,
                .updateControllerState = updateControllerStateImpl,
                .save = saveImpl,
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

    pub fn save(self: *Self, allocator: std.mem.Allocator, vfs: Vfs) Vfs.Error!void {
        return self.vtable.save(self.ptr, allocator, vfs);
    }
};

pub const Vfs = struct {
    pub const Error = std.mem.Allocator.Error || error{
        VfsError,
    };

    pub fn Interface(comptime T: type) type {
        return struct {
            deinit: *const fn (self: *T, allocator: std.mem.Allocator) void,
            readRom: *const fn (
                self: *T,
                allocator: std.mem.Allocator,
                alignment: std.mem.Alignment,
            ) Error![]u8,
            readBios: *const fn (
                self: *T,
                allocator: std.mem.Allocator,
                file_name: []const u8,
                alignment: std.mem.Alignment,
            ) Error![]u8,
            readSave: *const fn (
                self: *T,
                allocator: std.mem.Allocator,
                save_type: ?[]const u8,
                data: []u8,
            ) Error!usize,
            writeSave: *const fn (
                self: *T,
                allocator: std.mem.Allocator,
                save_type: ?[]const u8,
                data: []const u8,
            ) Error!void,
        };
    }

    const Self = @This();

    ptr: *anyopaque,
    vtable: *const Interface(anyopaque),

    pub fn init(
        inner: anytype,
        comptime iface: Interface(@typeInfo(@TypeOf(inner)).pointer.child),
    ) Self {
        const T = @typeInfo(@TypeOf(inner)).pointer.child;

        const gen = struct {
            fn deinitImpl(ptr: *anyopaque, allocator: std.mem.Allocator) void {
                const self: *T = @ptrCast(@alignCast(ptr));
                return @call(.always_inline, iface.deinit, .{ self, allocator });
            }

            fn readRomImpl(
                ptr: *anyopaque,
                allocator: std.mem.Allocator,
                alignment: std.mem.Alignment,
            ) Error![]u8 {
                const self: *T = @ptrCast(@alignCast(ptr));
                return @call(.always_inline, iface.readRom, .{
                    self,
                    allocator,
                    alignment,
                });
            }

            fn readBiosImpl(
                ptr: *anyopaque,
                allocator: std.mem.Allocator,
                file_name: []const u8,
                alignment: std.mem.Alignment,
            ) Error![]u8 {
                const self: *T = @ptrCast(@alignCast(ptr));
                return @call(.always_inline, iface.readBios, .{
                    self,
                    allocator,
                    file_name,
                    alignment,
                });
            }

            fn readSaveImpl(
                ptr: *anyopaque,
                allocator: std.mem.Allocator,
                save_type: ?[]const u8,
                data: []u8,
            ) Error!usize {
                const self: *T = @ptrCast(@alignCast(ptr));
                return @call(.always_inline, iface.readSave, .{
                    self,
                    allocator,
                    save_type,
                    data,
                });
            }

            fn writeSaveImpl(
                ptr: *anyopaque,
                allocator: std.mem.Allocator,
                save_type: ?[]const u8,
                data: []const u8,
            ) Error!void {
                const self: *T = @ptrCast(@alignCast(ptr));
                return @call(.always_inline, iface.writeSave, .{
                    self,
                    allocator,
                    save_type,
                    data,
                });
            }

            const vtable = Interface(anyopaque){
                .deinit = deinitImpl,
                .readRom = readRomImpl,
                .readBios = readBiosImpl,
                .readSave = readSaveImpl,
                .writeSave = writeSaveImpl,
            };
        };

        return .{
            .ptr = inner,
            .vtable = &gen.vtable,
        };
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        return self.vtable.deinit(self.ptr, allocator);
    }

    pub fn readRom(self: Self, allocator: std.mem.Allocator) Error![]u8 {
        return self.vtable.readRom(self.ptr, allocator, .of(u8));
    }

    pub fn readRomAligned(
        self: Self,
        allocator: std.mem.Allocator,
        comptime alignment: std.mem.Alignment,
    ) Error![]align(alignment.toByteUnits()) u8 {
        return @alignCast(try self.vtable.readRom(self.ptr, allocator, alignment));
    }

    pub fn readBios(self: Self, allocator: std.mem.Allocator, file_name: []const u8) Error![]u8 {
        return self.vtable.readBios(self.ptr, allocator, file_name, .of(u8));
    }

    pub fn readBiosAligned(
        self: Self,
        allocator: std.mem.Allocator,
        file_name: []const u8,
        comptime alignment: std.mem.Alignment,
    ) Error![]align(alignment.toByteUnits()) u8 {
        return @alignCast(try self.vtable.readBios(self.ptr, allocator, file_name, alignment));
    }

    pub fn readSave(
        self: Self,
        allocator: std.mem.Allocator,
        save_type: ?[]const u8,
        data: []u8,
    ) Error!usize {
        return self.vtable.readSave(self.ptr, allocator, save_type, data);
    }

    pub fn writeSave(
        self: Self,
        allocator: std.mem.Allocator,
        save_type: ?[]const u8,
        data: []const u8,
    ) Error!void {
        return self.vtable.writeSave(self.ptr, allocator, save_type, data);
    }
};
