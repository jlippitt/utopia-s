const std = @import("std");
const fw = @import("framework");
const Device = @import("../Device.zig");
const Core = @import("../Cpu.zig");
const Tlb = @import("./Cp0/Tlb.zig");

const exception_vector = 0x8000_0180;

const Register = enum(u5) {
    // zig fmt: off
    Index,    Random,   EntryLo0,    EntryLo1,
    Context,  PageMask, Wired,       R7,
    BadVAddr, Count,    EntryHi,     Compare,
    Status,   Cause,    EPC,         PRId,
    Config,   LLAddr,   WatchLo,     WatchHi,
    XContext, R21,      R22,         R23,
    R24,      R25,      ParityError, CacheError,
    TagLo,    TagHi,    ErrorEPC,    R31,
    // zig fmt: on
};

const MType = packed struct(u32) {
    _: u11,
    rd: Register,
    rt: Core.Register,
    rs: u5,
    opcode: u6,
};

pub const Interrupt = enum(u8) {
    rcp = 0x04,
    dd = 0x08,
    timer = 0x80,
};

const ExceptionType = enum(u5) {
    interrupt = 0,
    coprocessor_unusable = 11,
    trap = 13,
};

pub const Exception = union(ExceptionType) {
    interrupt: void,
    coprocessor_unusable: u2,
    trap: void,

    fn ce(self: @This()) u2 {
        return switch (self) {
            .coprocessor_unusable => |index| index,
            else => 0,
        };
    }
};

pub const Self = @This();

index: Tlb.Index = .{},
entry_lo: [2]Tlb.EntryLo = @splat(.{}),
context: Context = .{},
page_mask: Tlb.PageMask = .{},
wired: u6 = 0,
bad_vaddr: u64 = 0,
count_value: u32 = 0,
count_updated: u64 = 0,
entry_hi: Tlb.EntryHi = .{},
compare: u32 = 0,
status: Status = .{},
cause: Cause = .{},
epc: u64 = 0,
config: Config = .{},
ll_addr: u32 = 0,
watch_lo: WatchLo = .{},
watch_hi: WatchHi = .{},
x_context: XContext = .{},
error_epc: u64 = 0,
tag_lo: TagLo = .{},
tlb: Tlb = .init(),

pub fn init() Self {
    return .{};
}

pub fn fr(self: *const Self) bool {
    return self.status.fr;
}

pub fn setLLAddr(self: *Self, value: u32) void {
    self.ll_addr = value;
    fw.log.trace("  LLAddr: {X:08}", .{self.ll_addr});
}

pub fn clearInterrupt(self: *Self, interrupt: Interrupt) void {
    self.cause.ip &= ~@intFromEnum(interrupt);
    fw.log.trace("  Cause: {any}", .{self.cause});
}

pub fn raiseInterrupt(self: *Self, interrupt: Interrupt) void {
    self.cause.ip |= @intFromEnum(interrupt);
    fw.log.trace("  Cause: {any}", .{self.cause});
    self.checkPendingInterrupts();
}

pub fn except(self: *Self, exception: Exception, pc: u32, delay: bool) u32 {
    if (self.status.exl or self.status.erl) {
        fw.log.unimplemented("Nested exceptions", .{});
    }

    fw.log.debug("-- Exception: {any} --", .{exception});

    self.status.exl = true;
    fw.log.trace("  Status: {any}", .{self.status});

    self.cause.bd = delay;
    self.cause.exc_code = exception;
    self.cause.ce = exception.ce();
    fw.log.trace("  Cause: {any}", .{self.cause});

    self.epc = fw.num.signExtend(u64, if (delay) pc -% 4 else pc);
    fw.log.trace("  EPC: {X:016}", .{self.epc});

    return exception_vector;
}

fn get(self: *Self, reg: Register) u64 {
    return switch (reg) {
        .Index => @as(u32, @bitCast(self.index)),
        .EntryLo0 => @bitCast(self.entry_lo[0]),
        .EntryLo1 => @bitCast(self.entry_lo[1]),
        .PageMask => @bitCast(self.page_mask),
        .Context => @bitCast(self.context),
        .Wired => self.wired,
        .BadVAddr => self.bad_vaddr,
        .Count => self.getCurrentCount(),
        .EntryHi => @bitCast(self.entry_hi),
        .Compare => self.compare,
        .Status => @as(u32, @bitCast(self.status)),
        .Cause => @as(u32, @bitCast(self.cause)),
        .EPC => self.epc,
        .Config => @as(u32, @bitCast(self.config)),
        .LLAddr => self.ll_addr,
        .WatchLo => @as(u32, @bitCast(self.watch_lo)),
        .WatchHi => @as(u32, @bitCast(self.watch_hi)),
        .XContext => @bitCast(self.x_context),
        .TagLo => @as(u32, @bitCast(self.tag_lo)),
        .TagHi => 0,
        .ErrorEPC => self.error_epc,
        else => fw.log.todo("CPU CP0 register read: {t}", .{reg}),
    };
}

fn set(self: *Self, reg: Register, value: u64) void {
    switch (reg) {
        .Index => {
            fw.num.writeMasked(u32, @ptrCast(&self.index), @truncate(value), 0x8000_003f);
            fw.log.trace("  Index: {any}", .{self.index});
        },
        .EntryLo0 => {
            fw.num.writeMasked(u64, @ptrCast(&self.entry_lo[0]), value, 0x0000_0000_3fff_ffff);
            fw.log.trace("  EntryLo0: {any}", .{self.entry_lo[0]});
        },
        .EntryLo1 => {
            fw.num.writeMasked(u64, @ptrCast(&self.entry_lo[1]), value, 0x0000_0000_3fff_ffff);
            fw.log.trace("  EntryLo1: {any}", .{self.entry_lo[1]});
        },
        .PageMask => {
            fw.num.writeMasked(u64, @ptrCast(&self.page_mask), value, 0x0000_0000_01ff_e000);
            fw.log.trace("  PageMask: {any}", .{self.page_mask});
        },
        .Context => {
            fw.num.writeMasked(u64, @ptrCast(&self.context), value, 0xffff_ffff_ff80_0000);
            fw.log.trace("  Context: {any}", .{self.context});
        },
        .Wired => {
            self.wired = @truncate(value);
            fw.log.trace("  Wired: {d}", .{self.wired});
        },
        .BadVAddr => {
            self.bad_vaddr = value;
            fw.log.trace("  BadVAddr: {X:016}", .{self.bad_vaddr});
        },
        .Count => {
            self.count_value = @truncate(value);
            fw.log.trace("  Count: {X:08}", .{self.count_value});
            self.count_updated = self.getDevice().clock.getCycles();
            self.updateTimerEvent(self.count_value);
        },
        .EntryHi => {
            fw.num.writeMasked(u64, @ptrCast(&self.entry_hi), value, 0xc000_00ff_ffff_e0ff);
            fw.log.trace("  EntryHi: {any}", .{self.entry_hi});
        },
        .Compare => {
            self.compare = @truncate(value);
            fw.log.trace("  Compare: {X:08}", .{self.compare});
            self.clearInterrupt(.timer);
            self.updateTimerEvent(self.getCurrentCount());
        },
        .Status => {
            fw.num.writeMasked(
                u32,
                @ptrCast(&self.status),
                @truncate(value),
                0xfff7_ffff,
            );

            fw.log.trace("  Status: {any}", .{self.status});

            if (self.status.ksu != 0) {
                fw.log.warn("Unsupported: Non-kernel operating modes", .{});
            }

            if (self.status.kx) {
                fw.log.warn("Unsupported: 64-bit addressing", .{});
            }

            if (self.status.rp) {
                fw.log.warn("Unsupported: Low power mode", .{});
            }

            self.checkPendingInterrupts();
        },
        .Cause => {
            fw.num.writeMasked(
                u32,
                @ptrCast(&self.cause),
                @truncate(value),
                0x0000_0030,
            );

            fw.log.trace("  Cause: {any}", .{self.cause});

            self.checkPendingInterrupts();
        },
        .EPC => {
            self.epc = value;
            fw.log.trace("  EPC: {X:016}", .{self.epc});
        },
        .Config => {
            fw.num.writeMasked(
                u32,
                @ptrCast(&self.config),
                @truncate(value),
                0x0f00_800f,
            );

            fw.log.trace("  Config: {any}", .{self.config});

            if (!self.config.be) {
                fw.log.warn("Unsupported: Little-endian mode", .{});
            }

            if (self.config.ep != 0) {
                fw.log.warn("Unsupported: Non-default data transfer patterns", .{});
            }
        },
        .LLAddr => self.setLLAddr(@truncate(value)),
        .WatchLo => {
            fw.num.writeMasked(
                u32,
                @ptrCast(&self.watch_lo),
                @truncate(value),
                0xffff_fffb,
            );

            fw.log.trace("  WatchLo: {any}", .{self.watch_lo});
        },
        .WatchHi => {
            fw.num.writeMasked(
                u32,
                @ptrCast(&self.watch_hi),
                @truncate(value),
                0x0000_000f,
            );

            fw.log.trace("  WatchHi: {any}", .{self.watch_hi});
        },
        .XContext => {
            fw.num.writeMasked(u64, @ptrCast(&self.x_context), value, 0xffff_fffe_0000_0000);
            fw.log.trace("  XContext: {any}", .{self.x_context});
        },
        .TagLo => {
            fw.num.writeMasked(
                u32,
                @ptrCast(&self.tag_lo),
                @truncate(value),
                0x0fff_ffc0,
            );

            fw.log.trace("  TagLo: {any}", .{self.tag_lo});
        },
        .ErrorEPC => {
            self.error_epc = value;
            fw.log.trace("  ErrorEPC: {X:016}", .{self.error_epc});
        },
        .TagHi => {}, // Always zero
        else => fw.log.todo("CPU CP0 register write: {t} <= {X:016}", .{ reg, value }),
    }
}

fn checkPendingInterrupts(self: *Self) void {
    if (!self.status.ie or self.status.exl or self.status.erl) {
        return;
    }

    if ((self.cause.ip & self.status.im) == 0) {
        return;
    }

    self.getDevice().clock.reschedule(.cpu_interrupt, 0);
}

fn getCurrentCount(self: *const Self) u32 {
    const cycles = self.getDeviceConst().clock.getCycles();
    const delta = (cycles - self.count_updated) >> 2;
    return self.count_value +% @as(u32, @truncate(delta));
}

fn updateTimerEvent(self: *Self, count: u32) void {
    const diff = self.compare -% count;
    const delta = if (diff != 0) @as(u64, diff) else @as(u64, std.math.maxInt(u32)) + 1;
    self.getDevice().clock.reschedule(.cpu_timer, delta << 2);
}

fn getDevice(self: *Self) *Device {
    const core: *Core = @alignCast(@fieldParentPtr("cp0", self));
    return core.getDevice();
}

fn getDeviceConst(self: *const Self) *const Device {
    const core: *const Core = @alignCast(@fieldParentPtr("cp0", self));
    return core.getDeviceConst();
}

pub fn cop0(core: *Core, word: u32) void {
    const rs: u5 = @truncate(word >> 21);

    if (rs >= 0o20) {
        return switch (@as(u6, @truncate(word))) {
            0o02 => Tlb.tlbwi(core, word),
            0o30 => eret(core, word),
            else => |funct| fw.log.todo("CPU COP0 funct: {o:02}", .{funct}),
        };
    }

    switch (rs) {
        0o00 => mfc0(core, word),
        0o01 => dmfc0(core, word),
        0o04 => mtc0(core, word),
        0o05 => mtc0(core, word),
        else => fw.log.todo("CPU COP0 rs: {o:02}", .{rs}),
    }
}

fn mfc0(core: *Core, word: u32) void {
    const args: MType = @bitCast(word);
    fw.log.trace("{X:08}: MFC0 {t}, {t}", .{ core.pc, args.rt, args.rd });
    const result: u32 = @truncate(core.cp0.get(args.rd));
    core.set(args.rt, fw.num.signExtend(u64, result));
}

fn dmfc0(core: *Core, word: u32) void {
    const args: MType = @bitCast(word);
    fw.log.trace("{X:08}: DMFC0 {t}, {t}", .{ core.pc, args.rt, args.rd });
    core.set(args.rt, core.cp0.get(args.rd));
}

fn mtc0(core: *Core, word: u32) void {
    const args: MType = @bitCast(word);
    fw.log.trace("{X:08}: MTC0 {t}, {t}", .{ core.pc, args.rt, args.rd });
    const result: u32 = @truncate(core.get(args.rt));
    core.cp0.set(args.rd, fw.num.signExtend(u64, result));
}

fn dmtc0(core: *Core, word: u32) void {
    const args: MType = @bitCast(word);
    fw.log.trace("{X:08}: DMTC0 {t}, {t}", .{ core.pc, args.rt, args.rd });
    core.cp0.set(args.rd, core.get(args.rt));
}

fn eret(core: *Core, word: u32) void {
    _ = word;

    fw.log.trace("{X:08}: ERET", .{core.pc});

    if (core.cp0.status.erl) {
        core.cp0.status.erl = false;
        core.pc = @truncate(core.cp0.error_epc);
    } else {
        core.cp0.status.exl = false;
        core.pc = @truncate(core.cp0.epc);
    }

    fw.log.trace("  Status: {any}", .{core.cp0.status});

    core.ll_bit = false;
    core.pipe_state = .except;
    core.cp0.checkPendingInterrupts();
}

const Context = packed struct(u64) {
    __: u4 = 0,
    bad_vpn2: u19 = 0,
    pte_base: u41 = 0,
};

const Status = packed struct(u32) {
    ie: bool = false,
    exl: bool = false,
    erl: bool = false,
    ksu: u2 = 0,
    ux: bool = false,
    sx: bool = false,
    kx: bool = false,
    im: u8 = 0,
    de: bool = false,
    ce: bool = false,
    ch: bool = false,
    __0: bool = false,
    sr: bool = false,
    ts: bool = false,
    bev: bool = false,
    __1: u1 = 0,
    its: bool = false,
    re: bool = false,
    fr: bool = false,
    rp: bool = false,
    cu0: bool = false,
    cu1: bool = false,
    cu2: bool = false,
    cu3: bool = false,
};

const Cause = packed struct(u32) {
    __0: u2 = 0,
    exc_code: ExceptionType = .interrupt,
    __1: u1 = 0,
    ip: u8 = 0,
    __2: u12 = 0,
    ce: u2 = 0,
    __3: u1 = 0,
    bd: bool = false,
};

const Config = packed struct(u32) {
    k0: u3 = 0,
    cu: bool = false,
    __0: u11 = 0b110_0100_0110,
    be: bool = true,
    __1: u8 = 0b0000_0110,
    ep: u4 = 0,
    ec: u3 = 0b111,
    __2: u1 = 0,
};

const WatchLo = packed struct(u32) {
    write: bool = false,
    read: bool = false,
    __: u1 = 0,
    paddr0: u29 = 0,
};

const WatchHi = packed struct(u32) {
    paddr1: u4 = 0,
    __: u28 = 0,
};

const XContext = packed struct(u64) {
    __: u4 = 0,
    bad_vpn2: u27 = 0,
    region: u2 = 0,
    pte_base: u31 = 0,
};

const TagLo = packed struct(u32) {
    __0: u6 = 0,
    p_state: u2 = 0,
    p_tag_lo: u20 = 0,
    __1: u4 = 0,
};
