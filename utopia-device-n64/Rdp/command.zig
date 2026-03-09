const std = @import("std");
const fw = @import("framework");
const Core = @import("./Core.zig");
const Target = @import("./Target.zig");
const Tmem = @import("./Tmem.zig");
const fragment = @import("./fragment.zig");
const rectangle = @import("./command/rectangle.zig");
const triangle = @import("./command/triangle.zig");

pub const drawRectangle = rectangle.drawRectangle;
pub const RectangleType = rectangle.RectangleType;

pub const drawTriangle = triangle.drawTriangle;
pub const TriangleAttributes = triangle.TriangleAttributes;

pub fn syncLoad(core: *Core) void {
    _ = core;
    fw.log.debug("SYNC_LOAD", .{});
}

pub fn syncPipe(core: *Core) void {
    _ = core;
    fw.log.debug("SYNC_PIPE", .{});
}

pub fn syncTile(core: *Core) void {
    _ = core;
    fw.log.debug("SYNC_TILE", .{});
}

pub fn syncFull(core: *Core) Core.RenderError!void {
    fw.log.debug("SYNC_FULL", .{});
    try core.downloadImageData();
    return core.getRdp().syncFull();
}

pub fn setScissor(core: *Core, word: u64) void {
    const cmd: SetScissor = @bitCast(word);
    fw.log.debug("SET_SCISSOR: {any}", .{cmd});

    core.target.setImageHeight(cmd.yl >> 2);

    core.scissor = .{
        .x = cmd.xh >> 2,
        .y = cmd.yh >> 2,
        .w = (cmd.xl - cmd.xh) >> 2,
        .h = (cmd.yl - cmd.yh) >> 2,
    };
}

pub fn setPrimDepth(core: *Core, word: u64) void {
    const depth: u32 = @truncate(word);
    fw.log.debug("SET_PRIM_DEPTH: {X:08}", .{depth});
    core.options.prim_depth = @floatFromInt((depth >> 16) & 0x7fff);
    fw.log.debug("Primitive Depth: {d}", .{core.options.prim_depth});
}

pub fn setOtherModes(core: *Core, word: u64) error{SdlError}!void {
    const cmd: SetOtherModes = @bitCast(word);

    fw.log.debug("SET_OTHER_MODES: {any}", .{cmd});

    core.display_list.setCycleType(@enumFromInt(cmd.cycle_type));
    core.display_list.setBlendMode(cmd.blend.parse());
    core.display_list.setAlphaCvgSelect(cmd.alpha_cvg_select);
    core.display_list.setCvgTimesAlpha(cmd.cvg_times_alpha);
    core.display_list.setColorOnCvg(cmd.color_on_cvg);
    core.display_list.setAlphaCompare(cmd.alpha_compare_en);
    core.tmem.setTlutType(cmd.tlut_type);

    core.options.perspective_enable = cmd.persp_tex_en;
    fw.log.debug("Perspective Enable: {}", .{core.options.perspective_enable});

    core.options.z_source = cmd.z_source_sel;
    fw.log.debug("Z Source: {t}", .{core.options.z_source});

    core.options.pipeline.z_compare_enable = cmd.z_compare_en;
    fw.log.debug("Z Compare Enable: {}", .{core.options.pipeline.z_compare_enable});

    core.options.pipeline.z_update_enable = cmd.z_update_en;
    fw.log.debug("Z Update Enable: {}", .{core.options.pipeline.z_update_enable});

    const pipeline = try core.pipeline_cache.create(core.gpu, core.options.pipeline);
    core.display_list.setPipeline(pipeline);
}

pub fn loadTlut(core: *Core, word: u64) void {
    const cmd: Tmem.Tile.Size = @bitCast(word);
    fw.log.debug("LOAD_TLUT: {any}", .{cmd});
    core.tmem.loadTlut(core.getRdramConst(), cmd);
}

pub fn setTileSize(core: *Core, word: u64) void {
    const cmd: Tmem.Tile.Size = @bitCast(word);
    fw.log.debug("SET_TILE_SIZE: {any}", .{cmd});
    core.tmem.setTileSize(cmd);
}

pub fn loadBlock(core: *Core, word: u64) void {
    const cmd: Tmem.Tile.Size = @bitCast(word);
    fw.log.debug("LOAD_BLOCK: {any}", .{cmd});
    core.tmem.loadBlock(core.getRdramConst(), cmd);
}

pub fn loadTile(core: *Core, word: u64) void {
    const cmd: Tmem.Tile.Size = @bitCast(word);
    fw.log.debug("LOAD_TILE: {any}", .{cmd});
    core.tmem.loadTile(core.getRdramConst(), cmd);
}

pub fn setTile(core: *Core, word: u64) void {
    const cmd: Tmem.Tile.Descriptor = @bitCast(word);
    fw.log.debug("SET_TILE: {any}", .{cmd});
    core.tmem.setTileDescriptor(cmd);
}

pub fn setFillColor(core: *Core, word: u64) void {
    const color: u32 = @truncate(word);
    fw.log.debug("SET_FILL_COLOR: {X:08}", .{color});
    core.display_list.setFillColor(color);
}

pub fn setFogColor(core: *Core, word: u64) void {
    const color: u32 = @truncate(word);
    fw.log.debug("SET_FOG_COLOR: {X:08}", .{color});
    core.display_list.setFogColor(.fromRgba32Uint(color));
}

pub fn setBlendColor(core: *Core, word: u64) void {
    const color: u32 = @truncate(word);
    fw.log.debug("SET_BLEND_COLOR: {X:08}", .{color});
    core.display_list.setBlendColor(.fromRgba32Uint(color));
}

pub fn setPrimColor(core: *Core, word: u64) void {
    const color: u32 = @truncate(word);
    fw.log.debug("SET_PRIM_COLOR: {X:08}", .{color});
    core.display_list.setPrimColor(.fromRgba32Uint(color));
}

pub fn setEnvColor(core: *Core, word: u64) void {
    const color: u32 = @truncate(word);
    fw.log.debug("SET_ENV_COLOR: {X:08}", .{color});
    core.display_list.setEnvColor(.fromRgba32Uint(color));
}

pub fn setCombineMode(core: *Core, word: u64) void {
    const cmd: fragment.CombineParams = @bitCast(word);
    fw.log.debug("SET_COMBINE_MODE: {any}", .{cmd});
    core.display_list.setCombineMode(cmd.parse());
}

pub fn setTextureImage(core: *Core, word: u64) void {
    const cmd: SetImage = @bitCast(word);
    fw.log.debug("SET_TEXTURE_IMAGE: {any}", .{cmd});
    core.tmem.setImageParams(cmd.dram_addr, @as(u24, cmd.width + 1));
}

pub fn setDepthImage(core: *Core, word: u64) void {
    const address: u24 = @truncate(word);
    fw.log.debug("SET_DEPTH_IMAGE: {X:08}", .{address});
    core.target.setDepthImageAddress(address);
}

pub fn setColorImage(core: *Core, word: u64) void {
    const cmd: SetImage = @bitCast(word);

    fw.log.debug("SET_COLOR_IMAGE: {any}", .{cmd});

    const color_format: Target.ColorImageFormat = switch (cmd.format) {
        .rgba => switch (cmd.size) {
            .@"16" => .rgba16,
            .@"32" => .rgba32,
            else => fw.log.unimplemented("Color image RGBA bit depth: {t}", .{cmd.size}),
        },
        else => fw.log.unimplemented(
            "Color image format: {s}",
            .{std.enums.tagName(Core.PixelFormat, cmd.format) orelse "unknown"},
        ),
    };

    core.target.setColorImageParams(cmd.dram_addr, color_format, @as(u24, cmd.width) + 1);
    core.display_list.setPixelSize(cmd.size);
}

const SetScissor = packed struct(u64) {
    yl: u12,
    xl: u12,
    odd_line: bool,
    field: bool,
    __0: u6,
    yh: u12,
    xh: u12,
    __1: u8,
};

const SetOtherModes = packed struct(u64) {
    alpha_compare_en: bool,
    dither_alpha_en: bool,
    z_source_sel: Core.ZSource,
    antialias_en: bool,
    z_compare_en: bool,
    z_update_en: bool,
    image_read_en: bool,
    color_on_cvg: bool,
    cvg_dest: u2,
    z_mode: u2,
    cvg_times_alpha: bool,
    alpha_cvg_select: bool,
    force_blend: bool,
    _0: bool,
    blend: fragment.BlendParams,
    _1: u4,
    alpha_dither_sel: u2,
    rgb_dither_sel: u2,
    key_en: bool,
    convert_one: bool,
    bi_lerp_0: bool,
    bi_lerp_1: bool,
    mid_texel: bool,
    sample_type: bool,
    tlut_type: Tmem.TlutType,
    en_tlut: bool,
    tex_lod_en: bool,
    sharpen_tex_en: bool,
    detail_tex_en: bool,
    persp_tex_en: bool,
    cycle_type: u2,
    _2: bool,
    atomic_prim: bool,
    _3: u8,
};

const SetImage = packed struct(u64) {
    dram_addr: u24,
    __0: u8,
    width: u10,
    __1: u9,
    size: Core.PixelSize,
    format: Core.PixelFormat,
    __2: u8,
};
