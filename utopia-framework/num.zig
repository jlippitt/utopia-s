const std = @import("std");

pub fn truncate(
    comptime Dst: type,
    value: anytype,
) Dst {
    const Src = @TypeOf(value);
    const dst_bits = @typeInfo(Dst).int.bits;
    const src_bits = @typeInfo(Src).int.bits;
    const src_signedness = @typeInfo(Src).int.signedness;
    comptime std.debug.assert(dst_bits <= src_bits);
    const truncated: std.meta.Int(src_signedness, dst_bits) = @truncate(value);
    return @bitCast(truncated);
}

pub fn extend(
    comptime signedness: std.builtin.Signedness,
    comptime Dst: type,
    value: anytype,
) Dst {
    const Src = @TypeOf(value);
    const dst_bits = @typeInfo(Dst).int.bits;
    const src_bits = @typeInfo(Src).int.bits;
    comptime std.debug.assert(dst_bits >= src_bits);
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
