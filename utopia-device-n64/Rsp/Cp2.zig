const std = @import("std");
const fw = @import("framework");
const Core = @import("./Core.zig");
const compute = @import("./Cp2/compute.zig");
const memory = @import("./Cp2/memory.zig");

const Self = @This();

pub const Register = enum(u5) {
    // zig fmt: off
    V00, V01, V02, V03, V04, V05, V06, V07,
    V08, V09, V10, V11, V12, V13, V14, V15,
    V16, V17, V18, V19, V20, V21, V22, V23,
    V24, V25, V26, V27, V28, V29, V30, V31,
    // zig fmt: on
};

const ControlRegister = enum(u5) {
    // zig fmt: off
    VCO,  VCC,  VCE,  VC3,  VC4,  VC5,  VC6,  VC7,
    VC8,  VC9,  VC10, VC11, VC12, VC13, VC14, VC15,
    VC16, VC17, VC18, VC19, VC20, VC21, VC22, VC23,
    VC24, VC25, VC26, VC27, VC28, VC29, VC30, VC31,
    // zig fmt: on
};

fn MType(comptime T: type) type {
    return packed struct(u32) {
        __: u7,
        el: u4,
        vs: T,
        rt: Core.Register,
        rs: u5,
        opcode: u6,
    };
}

regs: [32]@Vector(8, u16) = @splat(@splat(0)),
acc: @Vector(8, u48) = @splat(0),
carry: @Vector(8, bool) = @splat(false),
not_equal: @Vector(8, bool) = @splat(false),
compare: @Vector(8, bool) = @splat(false),
clip_compare: @Vector(8, bool) = @splat(false),
compare_ext: @Vector(8, bool) = @splat(false),

pub fn init() Self {
    return .{};
}

pub fn get(self: *const Self, reg: Register) @Vector(8, u16) {
    return self.regs[@intFromEnum(reg)];
}

pub fn set(self: *Self, reg: Register, value: @Vector(8, u16)) void {
    self.regs[@intFromEnum(reg)] = value;
    fw.log.trace("  {t}: {any}", .{ reg, value });
}

pub fn getEl(self: *const Self, comptime T: type, reg: Register, el: u4) T {
    const bits = comptime @typeInfo(T).int.bits;
    const shift = @as(i32, 128) - (@as(i32, @intCast(el)) * 8) - bits;
    return @truncate(std.math.rotr(u128, @bitCast(self.get(reg)), shift));
}

pub fn setEl(self: *Self, comptime T: type, reg: Register, el: u4, value: T) void {
    const bits = comptime @typeInfo(T).int.bits;
    const shift = @as(i32, 128) - (@as(i32, @intCast(el)) * 8) - bits;
    var result: u128 = @bitCast(self.get(reg));
    result &= ~std.math.shl(u128, @as(u128, std.math.maxInt(T)), shift);
    result |= std.math.shl(u128, value, shift);
    self.set(reg, @bitCast(result));
}

pub fn setAccLow(self: *Self, value: @Vector(8, u16)) void {
    self.acc &= ~@as(@Vector(8, u48), @splat(0xffff));
    self.acc |= value;
}

pub fn broadcast(self: *const Self, reg: Register, el: u4) @Vector(8, u16) {
    const mask: [16]@Vector(8, i32) = .{
        .{ 0, 1, 2, 3, 4, 5, 6, 7 },
        .{ 0, 1, 2, 3, 4, 5, 6, 7 },
        .{ 1, 1, 3, 3, 5, 5, 7, 7 },
        .{ 0, 0, 2, 2, 4, 4, 6, 6 },
        .{ 3, 3, 3, 3, 7, 7, 7, 7 },
        .{ 2, 2, 2, 2, 6, 6, 6, 6 },
        .{ 1, 1, 1, 1, 5, 5, 5, 5 },
        .{ 0, 0, 0, 0, 4, 4, 4, 4 },
        @splat(7),
        @splat(6),
        @splat(5),
        @splat(4),
        @splat(3),
        @splat(2),
        @splat(1),
        @splat(0),
    };

    const value = self.get(reg);

    return switch (el) {
        inline else => |index| @shuffle(u16, value, undefined, mask[index]),
    };
}

pub fn cop2(core: *Core, word: u32) void {
    const rs: u5 = @truncate(word >> 21);

    if (rs >= 0o20) {
        @branchHint(.likely);

        return switch (@as(u6, @truncate(word))) {
            0o00 => compute.compute(.VMULF, core, word),
            0o01 => compute.compute(.VMULU, core, word),
            0o04 => compute.compute(.VMUDL, core, word),
            0o05 => compute.compute(.VMUDM, core, word),
            0o06 => compute.compute(.VMUDN, core, word),
            0o07 => compute.compute(.VMUDH, core, word),
            0o10 => compute.compute(.VMACF, core, word),
            0o11 => compute.compute(.VMACU, core, word),
            0o14 => compute.compute(.VMADL, core, word),
            0o15 => compute.compute(.VMADM, core, word),
            0o16 => compute.compute(.VMADN, core, word),
            0o17 => compute.compute(.VMADH, core, word),
            0o20 => compute.compute(.VADD, core, word),
            0o21 => compute.compute(.VSUB, core, word),
            0o23 => compute.compute(.VABS, core, word),
            0o24 => compute.compute(.VADDC, core, word),
            0o25 => compute.compute(.VSUBC, core, word),
            0o35 => compute.vsar(core, word),
            else => |funct| fw.log.todo("RSP COP2 funct: {o:02}", .{funct}),
        };
    }

    switch (rs) {
        0o00 => mfc2(core, word),
        0o02 => cfc2(core, word),
        0o04 => mtc2(core, word),
        0o06 => ctc2(core, word),
        else => fw.log.todo("RSP COP2 rs: {o:02}", .{rs}),
    }
}

pub fn lwc2(core: *Core, word: u32) void {
    switch (@as(u5, @truncate(word >> 11))) {
        0o00 => memory.load(.BV, core, word),
        0o01 => memory.load(.SV, core, word),
        0o02 => memory.load(.LV, core, word),
        0o03 => memory.load(.DV, core, word),
        0o04 => memory.load(.QV, core, word),
        // 0o05 => memory.load(.RV, core, word),
        else => |rd| fw.log.todo("RSP LWC2 rd: {o:02}", .{rd}),
    }
}

pub fn swc2(core: *Core, word: u32) void {
    switch (@as(u5, @truncate(word >> 11))) {
        0o00 => memory.store(.BV, core, word),
        0o01 => memory.store(.SV, core, word),
        0o02 => memory.store(.LV, core, word),
        0o03 => memory.store(.DV, core, word),
        0o04 => memory.store(.QV, core, word),
        // 0o05 => memory.store(.RV, core, word),
        else => |rd| fw.log.todo("RSP SWC2 rd: {o:02}", .{rd}),
    }
}

fn mfc2(core: *Core, word: u32) void {
    const args: MType(Register) = @bitCast(word);
    fw.log.trace("{X:03}: MFC2 {t}, {t}[E:{d}]", .{ core.pc, args.rt, args.vs, args.el });
    core.set(args.rt, fw.num.signExtend(u32, core.cp2.getEl(u16, args.vs, args.el)));
}

fn mtc2(core: *Core, word: u32) void {
    const args: MType(Register) = @bitCast(word);
    fw.log.trace("{X:03}: MTC2 {t}, {t}[E:{d}]", .{ core.pc, args.rt, args.vs, args.el });
    core.cp2.setEl(u16, args.vs, args.el, @truncate(core.get(args.rt)));
}

fn cfc2(core: *Core, word: u32) void {
    const args: MType(ControlRegister) = @bitCast(word);

    fw.log.trace("{X:03}: CFC2 {t}, {t}", .{ core.pc, args.rt, args.vs });

    const result: u16 = switch (@intFromEnum(args.vs) & 3) {
        0 => blk: {
            const carry: u8 = @bitCast(core.cp2.carry);
            const not_equal: u8 = @bitCast(core.cp2.not_equal);
            break :blk (@as(u16, @bitReverse(not_equal)) << 8) | @bitReverse(carry);
        },
        1 => blk: {
            const compare: u8 = @bitCast(core.cp2.compare);
            const clip_compare: u8 = @bitCast(core.cp2.clip_compare);
            break :blk (@as(u16, @bitReverse(clip_compare)) << 8) | @bitReverse(compare);
        },
        else => @bitReverse(@as(u8, @bitCast(core.cp2.compare_ext))),
    };

    core.set(args.rt, fw.num.signExtend(u32, result));
}

fn ctc2(core: *Core, word: u32) void {
    const args: MType(ControlRegister) = @bitCast(word);

    fw.log.trace("{X:03}: CTC2 {t}, {t}", .{ core.pc, args.rt, args.vs });

    const value = core.get(args.rt);

    switch (@intFromEnum(args.vs) & 3) {
        0 => {
            core.cp2.carry = @bitCast(@bitReverse(@as(u8, @truncate(value))));
            core.cp2.not_equal = @bitCast(@bitReverse(@as(u8, @truncate(value >> 8))));
        },
        1 => {
            core.cp2.compare = @bitCast(@bitReverse(@as(u8, @truncate(value))));
            core.cp2.clip_compare = @bitCast(@bitReverse(@as(u8, @truncate(value >> 8))));
        },
        else => core.cp2.compare_ext = @bitCast(@bitReverse(@as(u8, @truncate(value)))),
    }
}
