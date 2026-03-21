const std = @import("std");
const fw = @import("framework");

const size = 256;

const Self = @This();

address: u8 = 0,
data: *[size]u8,

pub fn init(arena: *std.heap.ArenaAllocator) error{OutOfMemory}!Self {
    const data = try arena.allocator().alloc(u8, size);

    return .{
        .data = data[0..size],
    };
}

pub fn get(self: *Self, index: u8) u8 {
    return self.data[index];
}

pub fn setAddress(self: *Self, value: u8) void {
    self.address = value;
    fw.log.debug("OAM Address: {X:02}", .{self.address});
}

pub fn read(self: *Self) u8 {
    fw.log.trace("OAM Read: {X:02} <= {X:02}", .{ self.address, self.data[self.address] });
    return self.data[self.address];
}

pub fn write(self: *Self, value: u8) void {
    self.data[self.address] = value;
    fw.log.trace("OAM Write: {X:02} <= {X:02}", .{ self.address, self.data[self.address] });
    self.address +%= 1;
}
