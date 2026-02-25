const std = @import("std");
const fw = @import("framework");
const Core = @import("../Cpu.zig");

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

const Self = @This();

count: u32 = 0,
compare: u32 = 0,
status: Status = .{},
cause: Cause = .{},
config: Config = .{},
tag_lo: TagLo = .{},

pub fn init() Self {
    return .{};
}

fn get(self: *Self, comptime bus: Core.Bus, reg: Register) u64 {
    _ = bus;

    return switch (reg) {
        .Count => self.count,
        .Compare => self.compare,
        .Status => @as(u32, @bitCast(self.status)),
        .Cause => @as(u32, @bitCast(self.cause)),
        .Config => @as(u32, @bitCast(self.config)),
        .TagLo => @as(u32, @bitCast(self.tag_lo)),
        .TagHi => 0,
        else => fw.log.todo("CPU CP0 register read: {t}", .{reg}),
    };
}

fn set(self: *Self, comptime bus: Core.Bus, reg: Register, value: u64) void {
    _ = bus;

    switch (reg) {
        .Count => {
            self.count = @truncate(value);
            fw.log.trace("  Count: {X:08}", .{self.count});
        },
        .Compare => {
            self.compare = @truncate(value);
            fw.log.trace("  Compare: {X:08}", .{self.compare});
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
        },
        .Cause => {
            fw.num.writeMasked(
                u32,
                @ptrCast(&self.cause),
                @truncate(value),
                0x0000_0030,
            );

            fw.log.trace("  Cause: {any}", .{self.cause});
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
        .TagLo => {
            fw.num.writeMasked(
                u32,
                @ptrCast(&self.tag_lo),
                @truncate(value),
                0x0fff_ffc0,
            );

            fw.log.trace("  TagLo: {any}", .{self.tag_lo});
        },
        .TagHi => {}, // Always zero
        else => fw.log.todo("CPU CP0 register write: {t} <= {X:016}", .{ reg, value }),
    }
}

pub fn cop0(comptime bus: Core.Bus, core: *Core, word: u32) void {
    switch (@as(u5, @truncate(word >> 21))) {
        0o00 => mfc0(bus, core, word),
        0o01 => dmfc0(bus, core, word),
        0o04 => mtc0(bus, core, word),
        0o05 => mtc0(bus, core, word),
        else => |rs| fw.log.todo("CPU COP0 rs: {o:02}", .{rs}),
    }
}

fn mfc0(comptime bus: Core.Bus, core: *Core, word: u32) void {
    const args: MType = @bitCast(word);
    fw.log.trace("{X:08}: MFC0 {t}, {t}", .{ core.pc, args.rt, args.rd });
    const result: u32 = @truncate(core.cp0.get(bus, args.rd));
    core.set(args.rt, fw.num.signExtend(u64, result));
}

fn dmfc0(comptime bus: Core.Bus, core: *Core, word: u32) void {
    const args: MType = @bitCast(word);
    fw.log.trace("{X:08}: DMFC0 {t}, {t}", .{ core.pc, args.rt, args.rd });
    core.set(args.rt, core.cp0.get(bus, args.rd));
}

fn mtc0(comptime bus: Core.Bus, core: *Core, word: u32) void {
    const args: MType = @bitCast(word);
    fw.log.trace("{X:08}: MTC0 {t}, {t}", .{ core.pc, args.rt, args.rd });
    const result: u32 = @truncate(core.get(args.rt));
    core.cp0.set(bus, args.rd, fw.num.signExtend(u64, result));
}

fn dmtc0(comptime bus: Core.Bus, core: *Core, word: u32) void {
    const args: MType = @bitCast(word);
    fw.log.trace("{X:08}: DMTC0 {t}, {t}", .{ core.pc, args.rt, args.rd });
    core.cp0.set(bus, args.rd, core.get(args.rt));
}

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
    exc_code: u5 = 0,
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

const TagLo = packed struct(u32) {
    __0: u6 = 0,
    p_state: u2 = 0,
    p_tag_lo: u20 = 0,
    __1: u4 = 0,
};
