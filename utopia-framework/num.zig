const std = @import("std");

pub fn extend(
    comptime signedness: std.builtin.Signedness,
    comptime T: type,
    value: anytype,
) T {
    const dst_bits = @typeInfo(T).int.bits;
    const src_bits = @typeInfo(@TypeOf(value)).int.bits;
    const sign_corrected: std.meta.Int(signedness, src_bits) = @bitCast(value);
    const sign_extended: std.meta.Int(signedness, dst_bits) = sign_corrected;
    return @bitCast(sign_extended);
}

pub fn signExtend(comptime T: type, value: anytype) T {
    return extend(.signed, T, value);
}

pub fn zeroExtend(comptime T: type, value: anytype) T {
    return extend(.unsigned, T, value);
}

pub fn writeMasked(comptime T: type, dst: *T, value: T, mask: T) void {
    dst.* = (dst.* & ~mask) | (value & mask);
}
