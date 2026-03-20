const std = @import("std");
const fw = @import("framework");

const dots_per_line = 341;

const pre_render_line = -1;
const vblank_line = 241;
const last_line = 260;

const Self = @This();

dot: u32 = 0,
line: i32 = 0,

pub fn init() Self {
    return .{};
}

pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("V={d} H={d}", .{ self.line, self.dot });
}

pub fn read(self: *Self, address: u16) u8 {
    _ = self;

    return switch (@as(u3, @truncate(address))) {
        2 => 0x80,
        else => fw.log.todo("PPU register read: {X:04}", .{address}),
    };
}

pub fn write(self: *Self, address: u16, value: u8) void {
    _ = self;

    switch (@as(u3, @truncate(address))) {
        else => fw.log.trace("TODO: PPU register write: {X:04} <= {X:02}", .{ address, value }),
    }
}

pub fn step(self: *Self) void {
    if (self.dot == dots_per_line) {
        @branchHint(.unlikely);
        self.dot = 0;
        self.line += 1;

        if (self.line > last_line) {
            self.line = pre_render_line;
            // TODO: Clear interrupt
        } else if (self.line == vblank_line) {
            // TODO: Raise interrupt
        }
    }

    self.dot += 1;
}
