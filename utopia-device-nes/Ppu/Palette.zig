const fw = @import("framework");

const ntsc_pal = @embedFile("./ntsc.pal");

const Self = @This();

data: [32]u6 = @splat(0),

pub fn init() Self {
    return .{};
}

pub fn color(self: *const Self, index: u5) fw.color.Abgr32 {
    // TODO: Emphasis/greyscale
    return colors[self.data[index]];
}

pub fn read(self: *Self, address: u15) u8 {
    // TODO: Greyscale
    const mask: u5 = if ((address & 0x03) != 0) 0x1f else 0x0f;
    const index = @as(u5, @truncate(address)) & mask;
    fw.log.trace("Palette Read: {X:02} => {X:02}", .{ index, self.data[index] });
    return self.data[index];
}

pub fn write(self: *Self, address: u15, value: u8) void {
    const mask: u5 = if ((address & 0x03) != 0) 0x1f else 0x0f;
    const index = @as(u5, @truncate(address)) & mask;
    self.data[index] = @truncate(value);
    fw.log.trace("Palette Write: {X:02} <= {X:02}", .{ index, self.data[index] });
}

const colors: [512]fw.color.Abgr32 = blk: {
    var array: [512]fw.color.Abgr32 = undefined;
    var index = 0;

    for (&array) |*entry| {
        entry.* = .{
            .r = ntsc_pal[index],
            .g = ntsc_pal[index + 1],
            .b = ntsc_pal[index + 2],
        };

        index += 3;
    }

    break :blk array;
};
