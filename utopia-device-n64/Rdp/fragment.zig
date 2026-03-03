const std = @import("std");

pub const CombineInput = enum(u32) {
    combined_rgb,
    texel0_rgb,
    texel1_rgb,
    prim_rgb,
    shade_rgb,
    env_rgb,
    key_center,
    key_scale,
    combined_alpha,
    texel0_alpha,
    texel1_alpha,
    prim_alpha,
    shade_alpha,
    env_alpha,
    lod_fraction,
    prim_lod_fraction,
    noise,
    convert_k4,
    convert_k5,
    constant1,
    constant0,
};

pub const CombineEquation = extern struct {
    sub_a: CombineInput = .combined_rgb,
    sub_b: CombineInput = .combined_rgb,
    mul: CombineInput = .combined_rgb,
    add: CombineInput = .combined_rgb,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("({t} - {t}) * {t} + {t}", .{
            self.sub_a,
            self.sub_b,
            self.mul,
            self.add,
        });
    }
};

pub const CombineMode = extern struct {
    rgb: CombineEquation = .{},
    a: CombineEquation = .{},
};

pub const CombineParams = packed struct(u64) {
    add_a_1: u3,
    sub_b_a_1: u3,
    add_r_1: u3,
    add_a_0: u3,
    sub_b_a_0: u3,
    add_r_0: u3,
    mul_a_1: u3,
    sub_a_a_1: u3,
    sub_b_r_1: u4,
    sub_b_r_0: u4,
    mul_r_1: u5,
    sub_a_r_1: u4,
    mul_a_0: u3,
    sub_a_a_0: u3,
    mul_r_0: u5,
    sub_a_r_0: u4,
    __: u8,

    pub fn parse(self: @This()) [2]CombineMode {
        return .{
            .{
                .rgb = parseRgb(
                    self.sub_a_r_0,
                    self.sub_b_r_0,
                    self.mul_r_0,
                    self.add_r_0,
                ),
                .a = parseAlpha(
                    self.sub_a_a_0,
                    self.sub_b_a_0,
                    self.mul_a_0,
                    self.add_a_0,
                ),
            },
            .{
                .rgb = parseRgb(
                    self.sub_a_r_1,
                    self.sub_b_r_1,
                    self.mul_r_1,
                    self.add_r_1,
                ),
                .a = parseAlpha(
                    self.sub_a_a_1,
                    self.sub_b_a_1,
                    self.mul_a_1,
                    self.add_a_1,
                ),
            },
        };
    }

    fn parseRgb(sub_a: u4, sub_b: u4, mul: u5, add: u3) CombineEquation {
        return .{
            .sub_a = switch (sub_a) {
                0 => .combined_rgb,
                1 => .texel0_rgb,
                2 => .texel1_rgb,
                3 => .prim_rgb,
                4 => .shade_rgb,
                5 => .env_rgb,
                6 => .constant1,
                7 => .noise,
                else => .constant0,
            },
            .sub_b = switch (sub_b) {
                0 => .combined_rgb,
                1 => .texel0_rgb,
                2 => .texel1_rgb,
                3 => .prim_rgb,
                4 => .shade_rgb,
                5 => .env_rgb,
                6 => .key_center,
                7 => .convert_k4,
                else => .constant0,
            },
            .mul = switch (mul) {
                0 => .combined_rgb,
                1 => .texel0_rgb,
                2 => .texel1_rgb,
                3 => .prim_rgb,
                4 => .shade_rgb,
                5 => .env_rgb,
                6 => .key_scale,
                7 => .combined_alpha,
                8 => .texel0_alpha,
                9 => .texel1_alpha,
                10 => .prim_alpha,
                11 => .shade_alpha,
                12 => .env_alpha,
                13 => .lod_fraction,
                14 => .prim_lod_fraction,
                15 => .convert_k5,
                else => .constant0,
            },
            .add = switch (add) {
                0 => .combined_rgb,
                1 => .texel0_rgb,
                2 => .texel1_rgb,
                3 => .prim_rgb,
                4 => .shade_rgb,
                5 => .env_rgb,
                6 => .constant1,
                7 => .constant0,
            },
        };
    }

    fn parseAlpha(sub_a: u3, sub_b: u3, mul: u3, add: u3) CombineEquation {
        return .{
            .sub_a = parseAlphaInput(sub_a),
            .sub_b = parseAlphaInput(sub_b),
            .mul = switch (mul) {
                0 => .lod_fraction,
                1 => .texel0_alpha,
                2 => .texel1_alpha,
                3 => .prim_alpha,
                4 => .shade_alpha,
                5 => .env_alpha,
                6 => .prim_lod_fraction,
                7 => .constant0,
            },
            .add = parseAlphaInput(add),
        };
    }

    fn parseAlphaInput(value: u3) CombineInput {
        return switch (value) {
            0 => .combined_alpha,
            1 => .texel0_alpha,
            2 => .texel1_alpha,
            3 => .prim_alpha,
            4 => .shade_alpha,
            5 => .env_alpha,
            6 => .constant1,
            7 => .constant0,
        };
    }
};

pub const BlendInput = enum(u32) {
    pixel_rgb,
    memory_rgb,
    blend_rgb,
    fog_rgb,
};

pub const BlendFactorA = enum(u32) {
    combined_alpha,
    fog_alpha,
    shade_alpha,
    constant_0,
};

pub const BlendFactorB = enum(u32) {
    one_minus_a,
    memory_alpha,
    constant_1,
    constant_0,
};

pub const BlendMode = extern struct {
    p: BlendInput = .pixel_rgb,
    a: BlendFactorA = .combined_alpha,
    m: BlendInput = .pixel_rgb,
    b: BlendFactorB = .one_minus_a,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("{t} * {t} + {t} * {t}", .{
            self.p,
            self.a,
            self.m,
            self.b,
        });
    }
};

pub const BlendParams = packed struct(u16) {
    b_m2b_1: u2,
    b_m2b_0: u2,
    b_m2a_1: u2,
    b_m2a_0: u2,
    b_m1b_1: u2,
    b_m1b_0: u2,
    b_m1a_1: u2,
    b_m1a_0: u2,

    pub fn parse(self: @This()) [2]BlendMode {
        return .{
            .{
                .p = @enumFromInt(self.b_m1a_0),
                .a = @enumFromInt(self.b_m1b_0),
                .m = @enumFromInt(self.b_m2a_0),
                .b = @enumFromInt(self.b_m2b_0),
            },
            .{
                .p = @enumFromInt(self.b_m1a_1),
                .a = @enumFromInt(self.b_m1b_1),
                .m = @enumFromInt(self.b_m2a_1),
                .b = @enumFromInt(self.b_m2b_1),
            },
        };
    }
};
