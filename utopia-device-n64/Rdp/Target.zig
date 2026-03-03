const sdl3 = @import("sdl3");
const fw = @import("framework");

const max_width = 1024;
const max_height = 1024;

const Self = @This();

pub const ColorImageFormat = enum {
    rgba16,
    rgba32,
};

pub const Surface = struct {
    color_image_texture: sdl3.gpu.Texture,
    color_image_address: u24,
    color_image_format: ColorImageFormat,
    image_width: u32,
    image_height: u32,
};

const Params = struct {
    color_image_address: u24 = 0,
    color_image_format: ColorImageFormat = .rgba32,
    image_width: u32 = 0,
    image_height: u32 = 0,
};

surface: ?Surface = null,
params: Params = .{},
params_changed: bool = false,
download_buffer: sdl3.gpu.TransferBuffer,

pub fn init(gpu: sdl3.gpu.Device) error{SdlError}!Self {
    const download_buffer = try gpu.createTransferBuffer(.{
        .usage = .download,
        .size = max_width * max_height * 4,
    });
    errdefer gpu.releaseTransferBuffer(download_buffer);

    return .{
        .download_buffer = download_buffer,
    };
}

pub fn deinit(self: *Self, gpu: sdl3.gpu.Device) void {
    gpu.releaseTransferBuffer(self.download_buffer);
}

pub fn paramsChanged(self: *const Self) bool {
    return self.params_changed;
}

pub fn getSurface(self: *const Self) ?*const Surface {
    return if (self.surface) |*surface| surface else null;
}

pub fn setColorImageParams(
    self: *Self,
    address: u24,
    format: ColorImageFormat,
    width: u32,
) void {
    self.params_changed = self.params_changed or
        address != self.params.color_image_address or
        format != self.params.color_image_format or
        width != self.params.image_width;

    self.params.color_image_address = address;
    fw.log.debug("Color Image Address: {X:08}", .{self.params.color_image_address});

    self.params.color_image_format = format;
    fw.log.debug("Color Image Format: {t}", .{self.params.color_image_format});

    self.params.image_width = width;
    fw.log.debug("Image Width: {d}", .{self.params.image_width});
}

pub fn setImageHeight(self: *Self, height: u32) void {
    self.params_changed = self.params_changed or height != self.params.image_height;

    self.params.image_height = height;
    fw.log.debug("Image Height: {d}", .{self.params.image_height});
}

pub fn update(self: *Self, gpu: sdl3.gpu.Device) error{SdlError}!void {
    if (!self.params_changed) {
        return;
    }

    if (self.params.image_width == 0 or self.params.image_height == 0) {
        self.surface = null;
        return;
    }

    const color_image_texture = try gpu.createTexture(.{
        .format = .r8g8b8a8_unorm,
        .usage = .{ .color_target = true },
        .width = self.params.image_width,
        .height = self.params.image_height,
        .layer_count_or_depth = 1,
        .num_levels = 1,
    });

    self.surface = .{
        .color_image_texture = color_image_texture,
        .color_image_address = self.params.color_image_address,
        .color_image_format = self.params.color_image_format,
        .image_width = self.params.image_width,
        .image_height = self.params.image_height,
    };

    self.params_changed = false;

    fw.log.debug("Target updated", .{});
}

pub fn downloadImageData(self: *Self, gpu: sdl3.gpu.Device, rdram: []u8) error{SdlError}!void {
    const surface = self.surface orelse return;

    const command_buffer = try gpu.acquireCommandBuffer();

    {
        const copy_pass = command_buffer.beginCopyPass();
        defer copy_pass.end();

        copy_pass.downloadFromTexture(.{
            .texture = surface.color_image_texture,
            .width = surface.image_width,
            .height = surface.image_height,
            .depth = 1,
        }, .{
            .transfer_buffer = self.download_buffer,
            .offset = 0,
        });
    }

    {
        const fence = try command_buffer.submitAndAcquireFence();
        defer gpu.releaseFence(fence);
        try gpu.waitForFences(true, &.{fence});
    }

    {
        const pixels = try gpu.mapTransferBuffer(self.download_buffer, true);
        defer gpu.unmapTransferBuffer(self.download_buffer);

        const image_size = surface.image_width * surface.image_height;

        switch (surface.color_image_format) {
            .rgba16 => {
                const dst_data: [][2]u8 = @ptrCast(
                    rdram[surface.color_image_address..][0..(image_size * 2)],
                );

                const src_data: []const [4]u8 = @ptrCast(pixels[0..(image_size * 4)]);

                for (dst_data, src_data) |*dst, src| {
                    const color = (@as(u16, src[0] >> 3) << 11) |
                        (@as(u16, src[1] >> 3) << 6) |
                        (@as(u16, src[2] >> 3) << 1) |
                        @as(u16, src[3] >> 7);

                    dst[0] = @truncate(color >> 8);
                    dst[1] = @truncate(color);
                }
            },
            .rgba32 => @memcpy(
                rdram[surface.color_image_address..][0..(image_size * 4)],
                pixels[0..(image_size * 4)],
            ),
        }
    }

    fw.log.debug("Color image downloaded to {X:08}", .{surface.color_image_address});
}
