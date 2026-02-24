const std = @import("std");

pub const DefaultArgs = struct {
    allocator: std.mem.Allocator,
};

pub const CliArgType = union(enum) {
    positional: void,
    flag: ?u8,
};

pub const CliArg = struct {
    desc: []const u8,
    type: CliArgType,
};

pub fn Interface(comptime Self: type) type {
    return struct {
        deinit: *const fn (self: *Self) void,
        runFrame: *const fn (self: *Self) void,
    };
}

pub const Device = struct {
    const Self = @This();

    ptr: *anyopaque,
    vtable: *const Interface(anyopaque),

    pub fn init(inner: anytype, comptime iface: Interface(@typeInfo(@TypeOf(inner)).pointer.child)) !Self {
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

            const vtable = Interface(anyopaque){
                .deinit = deinitImpl,
                .runFrame = runFrameImpl,
            };
        };

        return .{
            .ptr = inner,
            .vtable = &gen.vtable,
        };
    }

    pub fn deinit(self: Self) void {
        self.vtable.deinit(self.ptr);
    }

    pub fn runFrame(self: Self) void {
        self.vtable.runFrame(self.ptr);
    }
};
