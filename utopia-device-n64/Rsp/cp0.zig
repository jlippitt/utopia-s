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

pub fn cop0(core: *Core, word: u32) void {
    switch (@as(u5, @truncate(word >> 21))) {
        0o00 => mfc0(core, word),
        0o04 => mtc0(core, word),
        else => |rs| fw.log.todo("RSP COP0 rs: {o:02}", .{rs}),
    }
}

fn mfc0(core: *Core, word: u32) void {
    const args: MType = @bitCast(word);
    fw.log.trace("{X:08}: MFC0 {t}, {t}", .{ core.pc, args.rt, args.rd });
    core.set(args.rt, core.getRsp().readCp0Register(args.rd));
}

fn mtc0(core: *Core, word: u32) void {
    const args: MType = @bitCast(word);
    fw.log.trace("{X:08}: MTC0 {t}, {t}", .{ core.pc, args.rt, args.rd });
    core.getRsp().writeCp0Register(args.rd, core.get(args.rt));
}
