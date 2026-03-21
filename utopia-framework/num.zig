const std = @import("std");

pub fn WithSignedness(comptime signedness: std.builtin.Signedness, comptime T: type) type {
    return switch (@typeInfo(T)) {
        .int => |int| std.meta.Int(signedness, int.bits),
        .vector => |vector| blk: {
            const len = vector.len;
            const Int = @typeInfo(T).vector.child;
            const bits = @typeInfo(Int).int.bits;
            break :blk @Vector(len, std.meta.Int(signedness, bits));
        },
        else => @compileError("Type not supported by 'WithSignedness'"),
    };
}

pub fn Signed(comptime T: type) type {
    return WithSignedness(.signed, T);
}

pub fn Unsigned(comptime T: type) type {
    return WithSignedness(.unsigned, T);
}

pub fn signed(value: anytype) Signed(@TypeOf(value)) {
    return @bitCast(value);
}

pub fn unsigned(value: anytype) Unsigned(@TypeOf(value)) {
    return @bitCast(value);
}

pub fn truncate(
    comptime T: type,
    value: anytype,
) T {
    return switch (@typeInfo(T)) {
        .int => |int| blk: {
            const Src = @TypeOf(value);
            const dst_bits = int.bits;
            const src_bits = @typeInfo(Src).int.bits;
            const signedness = @typeInfo(Src).int.signedness;
            comptime std.debug.assert(dst_bits <= src_bits);
            const truncated: std.meta.Int(signedness, dst_bits) = @truncate(value);
            break :blk @bitCast(truncated);
        },
        .vector => |vector| blk: {
            const len = vector.len;
            const DstInt = vector.child;
            const Src = @TypeOf(value);
            const SrcInt = @typeInfo(Src).vector.child;
            const dst_bits = @typeInfo(DstInt).int.bits;
            const src_bits = @typeInfo(SrcInt).int.bits;
            const signedness = @typeInfo(SrcInt).int.signedness;
            comptime std.debug.assert(dst_bits <= src_bits);
            const truncated: @Vector(len, std.meta.Int(signedness, dst_bits)) = @truncate(value);
            break :blk @bitCast(truncated);
        },
        else => @compileError("Type not supported by 'truncate'"),
    };
}

pub fn extend(
    comptime signedness: std.builtin.Signedness,
    comptime T: type,
    value: anytype,
) T {
    return switch (@typeInfo(T)) {
        .int => |int| blk: {
            const Src = @TypeOf(value);
            const dst_bits = int.bits;
            const src_bits = @typeInfo(Src).int.bits;
            comptime std.debug.assert(dst_bits >= src_bits);
            const corrected: std.meta.Int(signedness, src_bits) = @bitCast(value);
            const extended: std.meta.Int(signedness, dst_bits) = corrected;
            break :blk @bitCast(extended);
        },
        .vector => |vector| blk: {
            const len = vector.len;
            const DstInt = vector.child;
            const Src = @TypeOf(value);
            const SrcInt = @typeInfo(Src).vector.child;
            const dst_bits = @typeInfo(DstInt).int.bits;
            const src_bits = @typeInfo(SrcInt).int.bits;
            comptime std.debug.assert(dst_bits >= src_bits);
            const corrected: @Vector(len, std.meta.Int(signedness, src_bits)) = @bitCast(value);
            const extended: @Vector(len, std.meta.Int(signedness, dst_bits)) = corrected;
            break :blk @bitCast(extended);
        },
        else => @compileError("Type not supported by 'extend'"),
    };
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

pub fn bit(src: anytype, index: std.math.Log2Int(@TypeOf(src))) bool {
    return (src & (@as(@TypeOf(src), 1) << index)) != 0;
}

pub fn setBit(comptime T: type, dst: *T, index: std.math.Log2Int(T), value: bool) void {
    writeMasked(T, dst, @as(T, @intFromBool(value)) << index, @as(T, 1) << index);
}
