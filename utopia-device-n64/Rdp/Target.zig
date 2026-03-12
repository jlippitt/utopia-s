const sdl3 = @import("sdl3");
const fw = @import("framework");

pub const msaa = 4;

const max_width = 1024;
const max_height = 1024;

const Self = @This();

pub const ColorImageFormat = enum {
    rgba16,
    rgba32,
};

pub const Surface = struct {
    color_texture: sdl3.gpu.Texture,
    color_texture_msaa: sdl3.gpu.Texture,
    color_address: u24,
    color_format: ColorImageFormat,
    depth_texture: sdl3.gpu.Texture,
    depth_texture_msaa: sdl3.gpu.Texture,
    depth_address: u24 = 0,
    image_width: u32,
    image_height: u32,
};

const Params = struct {
    color_address: u24 = 0,
    color_format: ColorImageFormat = .rgba32,
    depth_address: u24 = 0,
    image_width: u24 = 0,
    image_height: u24 = 0,
};

surface: ?Surface = null,
params: Params = .{},
params_changed: bool = false,
color_download_buffer: sdl3.gpu.TransferBuffer,
color_upload_buffer: sdl3.gpu.TransferBuffer,
color_image_dirty: bool = false,
depth_download_buffer: sdl3.gpu.TransferBuffer,
depth_upload_buffer: sdl3.gpu.TransferBuffer,
depth_image_dirty: bool = false,

pub fn init(gpu: sdl3.gpu.Device) error{SdlError}!Self {
    const color_download_buffer = try gpu.createTransferBuffer(.{
        .usage = .download,
        .size = max_width * max_height * 4,
    });
    errdefer gpu.releaseTransferBuffer(color_download_buffer);

    const color_upload_buffer = try gpu.createTransferBuffer(.{
        .usage = .upload,
        .size = max_width * max_height * 4,
    });
    errdefer gpu.releaseTransferBuffer(color_upload_buffer);

    const depth_download_buffer = try gpu.createTransferBuffer(.{
        .usage = .download,
        .size = max_width * max_height * 2,
    });
    errdefer gpu.releaseTransferBuffer(depth_download_buffer);

    const depth_upload_buffer = try gpu.createTransferBuffer(.{
        .usage = .upload,
        .size = max_width * max_height * 2,
    });
    errdefer gpu.releaseTransferBuffer(depth_upload_buffer);

    return .{
        .color_download_buffer = color_download_buffer,
        .color_upload_buffer = color_upload_buffer,
        .depth_download_buffer = depth_download_buffer,
        .depth_upload_buffer = depth_upload_buffer,
    };
}

pub fn deinit(self: *Self, gpu: sdl3.gpu.Device) void {
    if (self.surface) |surface| {
        gpu.releaseTexture(surface.depth_texture_msaa);
        gpu.releaseTexture(surface.depth_texture);
        gpu.releaseTexture(surface.color_texture_msaa);
        gpu.releaseTexture(surface.color_texture);
    }

    gpu.releaseTransferBuffer(self.depth_upload_buffer);
    gpu.releaseTransferBuffer(self.depth_download_buffer);
    gpu.releaseTransferBuffer(self.color_upload_buffer);
    gpu.releaseTransferBuffer(self.color_download_buffer);
}

pub fn paramsChanged(self: *Self) bool {
    if (!self.params_changed) {
        return false;
    }

    // Secondary check to make sure they *really* changed. It's apparently quite
    // common to adjust them and then set them back to what they were before.
    if (self.surface) |surface| {
        if (self.params.color_address == surface.color_address and
            self.params.color_format == surface.color_format and
            self.params.depth_address == surface.depth_address and
            self.params.image_width == surface.image_width and
            self.params.image_height <= surface.image_height)
        {
            self.params_changed = false;
            return false;
        }
    }

    return true;
}

pub fn getSurface(self: *const Self) ?*const Surface {
    return if (self.surface) |*surface| surface else null;
}

pub fn setColorImageParams(
    self: *Self,
    address: u24,
    format: ColorImageFormat,
    width: u24,
) void {
    self.params_changed = self.params_changed or
        address != self.params.color_address or
        format != self.params.color_format or
        width != self.params.image_width;

    self.params.color_address = address;
    fw.log.debug("Color Image Address: {X:08}", .{self.params.color_address});

    self.params.color_format = format;
    fw.log.debug("Color Image Format: {t}", .{self.params.color_format});

    self.params.image_width = width;
    fw.log.debug("Image Width: {d}", .{self.params.image_width});
}

pub fn setDepthImageAddress(self: *Self, address: u24) void {
    self.params_changed = self.params_changed or
        address != self.params.depth_address;

    self.params.depth_address = address;
    fw.log.debug("Depth Image Address: {X:08}", .{self.params.depth_address});
}

pub fn setImageHeight(self: *Self, height: u24) void {
    self.params_changed = self.params_changed or height != self.params.image_height;

    self.params.image_height = height;
    fw.log.debug("Image Height: {d}", .{self.params.image_height});
}

pub fn markDirty(self: *Self, depth: bool) void {
    self.color_image_dirty = true;
    self.depth_image_dirty = self.depth_image_dirty or depth;
}

pub fn update(self: *Self, gpu: sdl3.gpu.Device, rdram: []u8) error{SdlError}!void {
    if (self.params.image_width == 0 or self.params.image_height == 0) {
        self.surface = null;
        return;
    }

    try self.downloadImageData(gpu, rdram);

    if (self.surface) |surface| {
        gpu.releaseTexture(surface.depth_texture_msaa);
        gpu.releaseTexture(surface.depth_texture);
        gpu.releaseTexture(surface.color_texture_msaa);
        gpu.releaseTexture(surface.color_texture);
    }

    const color_texture = try gpu.createTexture(.{
        .format = .r8g8b8a8_unorm,
        .usage = .{ .color_target = true, .sampler = true },
        .width = self.params.image_width,
        .height = self.params.image_height,
        .layer_count_or_depth = 1,
        .num_levels = 1,
    });

    const color_texture_msaa = try gpu.createTexture(.{
        .format = .r8g8b8a8_unorm,
        .usage = .{ .color_target = true, .sampler = true },
        .width = self.params.image_width * msaa,
        .height = self.params.image_height * msaa,
        .layer_count_or_depth = 1,
        .num_levels = 1,
    });

    const depth_texture = try gpu.createTexture(.{
        .format = .depth16_unorm,
        .usage = .{ .depth_stencil_target = true, .sampler = true },
        .width = self.params.image_width,
        .height = self.params.image_height,
        .layer_count_or_depth = 1,
        .num_levels = 1,
    });

    const depth_texture_msaa = try gpu.createTexture(.{
        .format = .depth16_unorm,
        .usage = .{ .depth_stencil_target = true, .sampler = true },
        .width = self.params.image_width * msaa,
        .height = self.params.image_height * msaa,
        .layer_count_or_depth = 1,
        .num_levels = 1,
    });

    self.surface = .{
        .color_texture = color_texture,
        .color_texture_msaa = color_texture_msaa,
        .color_address = self.params.color_address,
        .color_format = self.params.color_format,
        .depth_texture = depth_texture,
        .depth_texture_msaa = depth_texture_msaa,
        .depth_address = self.params.depth_address,
        .image_width = self.params.image_width,
        .image_height = self.params.image_height,
    };

    try self.uploadImageData(gpu, rdram);

    self.params_changed = false;

    fw.log.debug("Target updated: {any}", .{self.params});
}

pub fn downloadImageData(self: *Self, gpu: sdl3.gpu.Device, rdram: []u8) error{SdlError}!void {
    const surface = self.surface orelse return;

    if (!self.color_image_dirty) {
        return;
    }

    const command_buffer = try gpu.acquireCommandBuffer();

    command_buffer.blitTexture(.{
        .source = .{
            .texture = surface.color_texture_msaa,
            .mip_level = 0,
            .layer_or_depth_plane = 0,
            .region = .{
                .x = 0,
                .y = 0,
                .w = surface.image_width * msaa,
                .h = surface.image_height * msaa,
            },
        },
        .destination = .{
            .texture = surface.color_texture,
            .mip_level = 0,
            .layer_or_depth_plane = 0,
            .region = .{
                .x = 0,
                .y = 0,
                .w = surface.image_width,
                .h = surface.image_height,
            },
        },
        .load_op = .do_not_care,
        .clear_color = .{},
        .flip_mode = .{},
        .filter = .linear,
        .cycle = true,
    });

    if (self.depth_image_dirty) {
        command_buffer.blitTexture(.{
            .source = .{
                .texture = surface.depth_texture_msaa,
                .mip_level = 0,
                .layer_or_depth_plane = 0,
                .region = .{
                    .x = 0,
                    .y = 0,
                    .w = surface.image_width * msaa,
                    .h = surface.image_height * msaa,
                },
            },
            .destination = .{
                .texture = surface.depth_texture,
                .mip_level = 0,
                .layer_or_depth_plane = 0,
                .region = .{
                    .x = 0,
                    .y = 0,
                    .w = surface.image_width,
                    .h = surface.image_height,
                },
            },
            .load_op = .do_not_care,
            .clear_color = .{},
            .flip_mode = .{},
            .filter = .nearest,
            .cycle = true,
        });
    }

    {
        const copy_pass = command_buffer.beginCopyPass();
        defer copy_pass.end();

        copy_pass.downloadFromTexture(
            .{
                .texture = surface.color_texture,
                .width = surface.image_width,
                .height = surface.image_height,
                .depth = 1,
            },
            .{
                .transfer_buffer = self.color_download_buffer,
                .offset = 0,
            },
        );

        if (self.depth_image_dirty) {
            copy_pass.downloadFromTexture(
                .{
                    .texture = surface.depth_texture,
                    .width = surface.image_width,
                    .height = surface.image_height,
                    .depth = 1,
                },
                .{
                    .transfer_buffer = self.depth_download_buffer,
                    .offset = 0,
                },
            );
        }
    }

    {
        const fence = try command_buffer.submitAndAcquireFence();
        defer gpu.releaseFence(fence);
        try gpu.waitForFences(true, &.{fence});
    }

    const image_size = surface.image_width * surface.image_height;

    {
        const pixels = try gpu.mapTransferBuffer(self.color_download_buffer, true);
        defer gpu.unmapTransferBuffer(self.color_download_buffer);

        switch (surface.color_format) {
            .rgba16 => {
                const dst_data: [][2]u8 = @ptrCast(
                    rdram[surface.color_address..][0..(image_size * 2)],
                );

                const src_data: []const [4]u8 = @ptrCast(pixels[0..(image_size * 4)]);

                for (dst_data, src_data) |*dst, src| {
                    dst.* = fw.color.Rgba16.fromAbgr32Bytes(src).toBytesBe();
                }
            },
            .rgba32 => @memcpy(
                rdram[surface.color_address..][0..(image_size * 4)],
                pixels[0..(image_size * 4)],
            ),
        }

        self.color_image_dirty = false;

        fw.log.debug("Color image downloaded to {X:08}", .{surface.color_address});
    }

    if (self.depth_image_dirty) {
        const pixels = try gpu.mapTransferBuffer(self.depth_download_buffer, true);
        defer gpu.unmapTransferBuffer(self.depth_download_buffer);

        @memcpy(
            rdram[surface.depth_address..][0..(image_size * 2)],
            pixels[0..(image_size * 2)],
        );

        self.depth_image_dirty = false;

        fw.log.debug("Depth image downloaded to {X:08}", .{surface.depth_address});
    }
}

fn uploadImageData(self: *Self, gpu: sdl3.gpu.Device, rdram: []const u8) error{SdlError}!void {
    const surface = self.surface orelse return;
    const image_size = surface.image_width * surface.image_height;

    {
        const pixels = try gpu.mapTransferBuffer(self.color_upload_buffer, true);
        defer gpu.unmapTransferBuffer(self.color_upload_buffer);

        switch (surface.color_format) {
            .rgba16 => {
                const dst_data: [][4]u8 = @ptrCast(pixels[0..(image_size * 4)]);

                const src_data: []const [2]u8 = @ptrCast(
                    rdram[surface.color_address..][0..(image_size * 2)],
                );

                for (dst_data, src_data) |*dst, src| {
                    dst.* = fw.color.Rgba16.fromBytesBe(src).toAbgr32Bytes();
                }
            },
            .rgba32 => @memcpy(
                pixels[0..(image_size * 4)],
                rdram[surface.color_address..][0..(image_size * 4)],
            ),
        }
    }

    {
        const pixels = try gpu.mapTransferBuffer(self.depth_upload_buffer, true);
        defer gpu.unmapTransferBuffer(self.depth_upload_buffer);

        @memcpy(
            pixels[0..(image_size * 2)],
            rdram[surface.depth_address..][0..(image_size * 2)],
        );
    }

    const command_buffer = try gpu.acquireCommandBuffer();

    {
        const copy_pass = command_buffer.beginCopyPass();
        defer copy_pass.end();

        copy_pass.uploadToTexture(
            .{
                .transfer_buffer = self.color_upload_buffer,
                .offset = 0,
            },
            .{
                .texture = surface.color_texture,
                .width = surface.image_width,
                .height = surface.image_height,
                .depth = 1,
            },
            true,
        );

        copy_pass.uploadToTexture(
            .{
                .transfer_buffer = self.depth_upload_buffer,
                .offset = 0,
            },
            .{
                .texture = surface.depth_texture,
                .width = surface.image_width,
                .height = surface.image_height,
                .depth = 1,
            },
            true,
        );
    }

    command_buffer.blitTexture(.{
        .source = .{
            .texture = surface.color_texture,
            .mip_level = 0,
            .layer_or_depth_plane = 0,
            .region = .{
                .x = 0,
                .y = 0,
                .w = surface.image_width,
                .h = surface.image_height,
            },
        },
        .destination = .{
            .texture = surface.color_texture_msaa,
            .mip_level = 0,
            .layer_or_depth_plane = 0,
            .region = .{
                .x = 0,
                .y = 0,
                .w = surface.image_width * msaa,
                .h = surface.image_height * msaa,
            },
        },
        .load_op = .do_not_care,
        .clear_color = .{},
        .flip_mode = .{},
        .filter = .nearest,
        .cycle = true,
    });

    command_buffer.blitTexture(.{
        .source = .{
            .texture = surface.depth_texture,
            .mip_level = 0,
            .layer_or_depth_plane = 0,
            .region = .{
                .x = 0,
                .y = 0,
                .w = surface.image_width,
                .h = surface.image_height,
            },
        },
        .destination = .{
            .texture = surface.depth_texture_msaa,
            .mip_level = 0,
            .layer_or_depth_plane = 0,
            .region = .{
                .x = 0,
                .y = 0,
                .w = surface.image_width * msaa,
                .h = surface.image_height * msaa,
            },
        },
        .load_op = .do_not_care,
        .clear_color = .{},
        .flip_mode = .{},
        .filter = .nearest,
        .cycle = true,
    });

    try command_buffer.submit();

    fw.log.debug("Color image uploaded from {X:08}", .{surface.color_address});
    fw.log.debug("Depth image uploaded from {X:08}", .{surface.depth_address});
}
