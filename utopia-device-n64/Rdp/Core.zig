const fw = @import("framework");

const Self = @This();

pub fn init() Self {
    return .{};
}

pub fn step(self: *Self, word: u64) void {
    _ = self;
    fw.log.debug("{X:016}", .{word});
}
