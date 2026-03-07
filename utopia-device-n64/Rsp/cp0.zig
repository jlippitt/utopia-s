const fw = @import("framework");
const Core = @import("./Core.zig");

pub const Register = enum(u4) {
    SP_DMA_SPADDR,
    SP_DMA_RAMADDR,
    SP_DMA_RDLEN,
    SP_DMA_WRLEN,
    SP_STATUS,
    SP_DMA_FULL,
    SP_DMA_BUSY,
    SP_SEMAPHORE,
    DPC_START,
    DPC_END,
    DPC_CURRENT,
    DPC_STATUS,
    DPC_CLOCK,
    DPC_CMD_BUSY,
    DPC_PIPE_BUSY,
    DPC_TMEM_BUSY,
};

const MType = packed struct(u32) {
    __0: u11,
    rd: Register,
    __1: u1,
    rt: Core.Register,
    rs: u5,
    opcode: u6,
};

pub fn cop0(word: u32) *const Core.Instruction {
    return table[(@as(u5, @truncate(word >> 21)))];
}

fn mfc0(core: *Core, word: u32) void {
    const args: MType = @bitCast(word);
    fw.log.trace("{X:03}: MFC0 {t}, {t}", .{ core.pc, args.rt, args.rd });
    core.set(args.rt, core.getRsp().readCp0Register(args.rd));
}

fn mtc0(core: *Core, word: u32) void {
    const args: MType = @bitCast(word);
    fw.log.trace("{X:03}: MTC0 {t}, {t}", .{ core.pc, args.rt, args.rd });
    core.getRsp().writeCp0Register(args.rd, core.get(args.rt));
}

const table: [32]*const Core.Instruction = blk: {
    var ops: [32]*const Core.Instruction = @splat(Core.reserved);
    ops[0o00] = mfc0;
    ops[0o04] = mtc0;
    break :blk ops;
};
