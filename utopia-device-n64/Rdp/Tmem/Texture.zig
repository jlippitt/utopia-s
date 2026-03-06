const std = @import("std");
const sdl3 = @import("sdl3");
const fw = @import("framework");

const Self = @This();

ref_count: u32 = 0,
texture: ?sdl3.gpu.Texture = null,

pub fn init() Self {
    return .{};
}

pub fn hasRefs(self: *const Self) bool {
    return self.ref_count != 0;
}

pub fn isActive(self: *const Self) bool {
    return self.texture != null;
}

pub fn getBinding(self: *const Self) sdl3.gpu.Texture {
    std.debug.assert(self.hasRefs());
    std.debug.assert(self.isActive());
    return self.texture.?;
}

pub fn activate(
    self: *Self,
    gpu: sdl3.gpu.Device,
    upload_buffer: sdl3.gpu.TransferBuffer,
    width: u32,
    height: u32,
    pixels: []const u8,
) error{SdlError}!void {
    std.debug.assert(!self.hasRefs());
    std.debug.assert(!self.isActive());

    const texture = try gpu.createTexture(.{
        .format = .r8g8b8a8_unorm,
        .usage = .{ .sampler = true },
        .width = width,
        .height = height,
        .layer_count_or_depth = 1,
        .num_levels = 1,
    });

    {
        const dst_pixels = try gpu.mapTransferBuffer(upload_buffer, true);
        defer gpu.unmapTransferBuffer(upload_buffer);
        @memcpy(dst_pixels[0..pixels.len], pixels);
    }

    const command_buffer = try gpu.acquireCommandBuffer();

    {
        const copy_pass = command_buffer.beginCopyPass();
        defer copy_pass.end();

        copy_pass.uploadToTexture(
            .{
                .transfer_buffer = upload_buffer,
                .offset = 0,
            },
            .{
                .texture = texture,
                .width = width,
                .height = height,
                .depth = 1,
            },
            true,
        );
    }

    try command_buffer.submit();

    self.texture = texture;
}

pub fn deactivate(self: *Self, gpu: sdl3.gpu.Device) void {
    std.debug.assert(!self.hasRefs());
    std.debug.assert(self.isActive());
    gpu.releaseTexture(self.texture.?);
    self.texture = null;
}

pub fn ref(self: *Self) void {
    self.ref_count += 1;
}

pub fn unref(self: *Self) void {
    self.ref_count -= 1;
}
