const std = @import("std");
const fw = @import("framework");
const Core = @import("../../Cpu.zig");
const Cp1 = @import("../Cp1.zig");

const ConvertOp = enum {
    CVT,
    ROUND,
    TRUNC,
    CEIL,
    FLOOR,
};

pub fn cvt(
    comptime op: ConvertOp,
    comptime dst_fmt: Cp1.Format,
    comptime src_fmt: Cp1.Format,
) Core.Instruction {
    return struct {
        fn instr(core: *Core, word: u32) void {
            Cp1.checkUsable(core);

            const args: Cp1.RType = @bitCast(word);

            fw.log.trace("{X:08}: {t}.{t}.{t} {t}, {t}", .{
                core.pc,
                op,
                dst_fmt,
                src_fmt,
                args.fd,
                args.fs,
            });

            const value = core.cp1.get(src_fmt, args.fs);

            core.cp1.set(
                dst_fmt,
                args.fd,
                std.math.lossyCast(dst_fmt.Type(), switch (comptime op) {
                    .CVT => value,
                    .ROUND => roundEven(value),
                    .TRUNC => @trunc(value),
                    .CEIL => @ceil(value),
                    .FLOOR => @floor(value),
                }),
            );
        }
    }.instr;
}

fn roundEven(value: anytype) @TypeOf(value) {
    return if (@mod(value, 1.0) == 0.5)
        @round(value * 2.0) / 2.0
    else
        @round(value);
}
