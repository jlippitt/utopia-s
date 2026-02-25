pub fn readLe(comptime T: type, data: []const u8, address: usize) T {
    const size = comptime @typeInfo(T).int.bits / 8;
    const ptr = data[address..][0..size];
    return @bitCast(ptr.*);
}

pub fn readBe(comptime T: type, data: []const u8, address: usize) T {
    const size = comptime @typeInfo(T).int.bits / 8;
    const ptr = data[address..][0..size];
    return @byteSwap(@as(T, @bitCast(ptr.*)));
}

pub fn writeLe(comptime T: type, data: []u8, address: usize, value: T) void {
    const size = comptime @typeInfo(T).int.bits / 8;
    const ptr = data[address..][0..size];
    ptr.* = @bitCast(value);
}

pub fn writeBe(comptime T: type, data: []u8, address: usize, value: T) void {
    const size = comptime @typeInfo(T).int.bits / 8;
    const ptr = data[address..][0..size];
    ptr.* = @bitCast(@byteSwap(value));
}

pub fn writeMaskedLe(comptime T: type, data: []u8, address: usize, value: T, mask: T) void {
    const size = comptime @typeInfo(T).int.bits / 8;
    const ptr = data[address..][0..size];
    const prev_value: T = @bitCast(ptr.*);
    const result = (prev_value & ~mask) | (value & mask);
    ptr.* = @bitCast(result);
}

pub fn writeMaskedBe(comptime T: type, data: []u8, address: usize, value: T, mask: T) void {
    const size = comptime @typeInfo(T).int.bits / 8;
    const ptr = data[address..][0..size];
    const prev_value: T = @bitCast(ptr.*);
    const result = @byteSwap((@byteSwap(prev_value) & ~mask) | (value & mask));
    ptr.* = @bitCast(result);
}
