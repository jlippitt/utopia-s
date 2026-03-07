const fw = @import("framework");
const Core = @import("../../Cpu.zig");
const Cp1 = @import("../Cp1.zig");

pub const BinaryOp = enum {
    ADD,
    SUB,
    MUL,
    DIV,
};

pub fn binary(comptime op: BinaryOp, comptime fmt: Cp1.Format) Core.Instruction {
    return struct {
        fn instr(core: *Core, word: u32) void {
            Cp1.checkUsable(core);

            const args: Cp1.RType = @bitCast(word);

            fw.log.trace("{X:08}: {t}.{t} {t}, {t}, {t}", .{
                core.pc,
                op,
                fmt,
                args.fd,
                args.fs,
                args.ft,
            });

            const lhs = core.cp1.get(fmt, args.fs);
            const rhs = core.cp1.get(fmt, args.ft);

            core.cp1.set(fmt, args.fd, switch (comptime op) {
                .ADD => lhs + rhs,
                .SUB => lhs - rhs,
                .MUL => lhs * rhs,
                .DIV => lhs / rhs,
            });
        }
    }.instr;
}

pub const UnaryOp = enum {
    SQRT,
    ABS,
    MOV,
    NEG,
};

pub fn unary(comptime op: UnaryOp, comptime fmt: Cp1.Format) Core.Instruction {
    return struct {
        fn instr(core: *Core, word: u32) void {
            Cp1.checkUsable(core);

            const args: Cp1.RType = @bitCast(word);

            fw.log.trace("{X:08}: {t}.{t} {t}, {t}", .{
                core.pc,
                op,
                fmt,
                args.fd,
                args.fs,
            });

            const value = core.cp1.get(fmt, args.fs);

            core.cp1.set(fmt, args.fd, switch (comptime op) {
                .SQRT => @sqrt(value),
                .ABS => @abs(value),
                .MOV => value,
                .NEG => -value,
            });
        }
    }.instr;
}
