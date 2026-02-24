const fw = @import("framework");
const alu = @import("./Cpu/alu.zig");

const Self = @This();

const cold_reset_vector = 0xbfc0_0000;

// zig fmt: off
pub const Register = enum(u5) {
    ZERO, AT, V0, V1, A0, A1, A2, A3,
    T0,   T1, T2, T3, T4, T5, T6, T7,
    S0,   S1, S2, S3, S4, S5, S6, S7,
    T8,   T9, K0, K1, GP, SP, FP, RA,
};
// zig fmt: on

pub const PipeState = enum {
    normal,
    branch,
    delay,
    except,
};

pub const IType = packed struct(u32) {
    imm: u16,
    rt: Register,
    rs: Register,
    opcode: u6,
};

pub const Bus = struct {
    read: fn (self: *Self, address: u32) u32,
    write: fn (self: *Self, address: u32, value: u32, mask: u32) void,
};

pc: u32 = cold_reset_vector,
target_pc: u32 = 0,
pipe_state: PipeState = .normal,
regs: [32]u64 = @splat(0),

pub fn init() Self {
    return .{};
}

pub fn step(self: *Self, comptime bus: Bus) void {
    const word = bus.read(self, self.mapAddress(self.pc) orelse return);

    switch (@as(u6, @truncate(word >> 26))) {
        0o17 => alu.lui(self, word),
        else => |opcode| fw.log.todo("CPU opcode: {o:02}", .{opcode}),
    }

    if (self.pipe_state == .delay) {
        @branchHint(.unlikely);
        self.pc = self.target_pc;
    } else if (self.pipe_state != .except) {
        @branchHint(.likely);
        self.pc +%= 4;
    }

    if (self.pipe_state == .branch) {
        @branchHint(.unlikely);
        self.pipe_state = .delay;
    } else {
        self.pipe_state = .normal;
    }
}

pub fn get(self: *const Self, reg: Register) u64 {
    return self.regs[@intFromEnum(reg)];
}

pub fn set(self: *Self, reg: Register, value: u64) void {
    self.regs[@intFromEnum(reg)] = value;
    self.regs[@intFromEnum(Register.ZERO)] = 0;

    if (reg != Register.ZERO) {
        fw.log.trace("  {t}: {X:016}", .{ reg, value });
    }
}

pub fn mapAddress(self: *Self, paddr: u32) ?u32 {
    _ = self;

    if ((paddr & 0xc000_0000) == 0x8000_0000) {
        @branchHint(.likely);
        return paddr & 0x1fff_ffff;
    }

    fw.log.todo("TLB lookups", .{});
}
