const builtin = @import("builtin");
const std = @import("std");
const fw = @import("framework");
const sdl3 = @import("sdl3");
const Rdp = @import("../Rdp.zig");
const Target = @import("./Target.zig");
const command = @import("./command.zig");

const max_command_length = 22;

const Self = @This();

gpu: sdl3.gpu.Device,
target: Target,
word_buf: std.ArrayListUnmanaged(u64),

pub fn init(arena: *std.heap.ArenaAllocator) error{ SdlError, OutOfMemory }!Self {
    const gpu = try sdl3.gpu.Device.init(.{ .spirv = true }, builtin.mode == .Debug, null);
    errdefer gpu.deinit();

    var target = try Target.init(gpu);
    errdefer target.deinit(gpu);

    const word_buf = try std.ArrayListUnmanaged(u64).initCapacity(
        arena.allocator(),
        max_command_length,
    );

    return .{
        .gpu = gpu,
        .target = target,
        .word_buf = word_buf,
    };
}

pub fn deinit(self: *Self) void {
    self.target.deinit(self.gpu);
    self.gpu.deinit();
}

pub fn downloadImageData(self: *Self) !void {
    try self.target.update(self.gpu);
    try self.render();
    try self.target.downloadImageData(self.gpu, self.getRdram());
}

pub fn render(self: *Self) error{SdlError}!void {
    const surface = self.target.getSurface() orelse {
        return;
    };

    const color_target: sdl3.gpu.ColorTargetInfo = .{
        .texture = surface.color_image_texture,
        .load = .clear,
        .store = .store,
        .clear_color = .{
            .r = 1.0,
            .g = 1.0,
            .b = 1.0,
            .a = 1.0,
        },
    };

    const command_buffer = try self.gpu.acquireCommandBuffer();

    {
        const render_pass = command_buffer.beginRenderPass(&.{color_target}, null);
        defer render_pass.end();
    }

    try command_buffer.submit();
}

pub fn step(self: *Self, word: u64) !void {
    self.word_buf.appendAssumeCapacity(word);

    switch (@as(u6, @truncate(self.word_buf.items[0] >> 56))) {
        0x29 => try command.syncFull(self),
        0x2d => command.setScissor(self, word),
        0x3f => command.setColorImage(self, word),
        else => |cmd| fw.log.debug("Unknown Command: {X:02}", .{cmd}),
    }

    _ = self.word_buf.pop();
}

pub fn getRdp(self: *Self) *Rdp {
    return @alignCast(@fieldParentPtr("core", self));
}

pub fn getRdram(self: *Self) []u8 {
    return self.getRdp().getDevice().rdram;
}
