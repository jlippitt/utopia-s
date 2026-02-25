pub fn setFlag(dst: anytype, comptime field: []const u8, value: u32, shift: u5) void {
    switch (@as(u2, @truncate(value >> shift))) {
        1 => @field(dst, field) = false,
        2 => @field(dst, field) = true,
        else => {},
    }
}
