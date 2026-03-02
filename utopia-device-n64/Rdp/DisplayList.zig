const fw = @import("framework");
const std = @import("std");
const Core = @import("./Core.zig");
const sdl3 = @import("sdl3");

const max_display_groups = 256;
const max_buffer_len = 1024;
const index_buffer_size = @sizeOf(Core.Index) * max_buffer_len;
const vertex_buffer_size = @sizeOf(Core.Vertex) * max_buffer_len;

pub const triangle_size = 3;
pub const rectangle_size = 6;

pub const CycleType = enum(u32) {
    one_cycle,
    two_cycle,
    copy,
    fill,
};

const FragmentState = extern struct {
    fill_color: [4]f32 = @splat(0.0),
    cycle_type: CycleType = .one_cycle,
};

pub const DisplayGroup = struct {
    len: u32,
    frag_state: FragmentState,
};

const Self = @This();

display_groups: std.ArrayList(DisplayGroup),
indices: std.ArrayList(Core.Index),
vertices: std.ArrayList(Core.Vertex),
index_buffer: sdl3.gpu.Buffer,
vertex_buffer: sdl3.gpu.Buffer,
index_upload_buffer: sdl3.gpu.TransferBuffer,
vertex_upload_buffer: sdl3.gpu.TransferBuffer,
frag_state: FragmentState = .{},
frag_state_changed: bool = false,

pub fn init(
    arena: *std.heap.ArenaAllocator,
    gpu: sdl3.gpu.Device,
) error{ SdlError, OutOfMemory }!Self {
    const index_buffer = try gpu.createBuffer(.{
        .size = index_buffer_size,
        .usage = .{ .index = true },
    });
    errdefer gpu.releaseBuffer(index_buffer);

    const vertex_buffer = try gpu.createBuffer(.{
        .size = vertex_buffer_size,
        .usage = .{ .vertex = true },
    });
    errdefer gpu.releaseBuffer(vertex_buffer);

    const index_upload_buffer = try gpu.createTransferBuffer(.{
        .size = index_buffer_size,
        .usage = .upload,
    });
    errdefer gpu.releaseTransferBuffer(index_upload_buffer);

    const vertex_upload_buffer = try gpu.createTransferBuffer(.{
        .size = vertex_buffer_size,
        .usage = .upload,
    });
    errdefer gpu.releaseTransferBuffer(vertex_upload_buffer);

    return .{
        .display_groups = try .initCapacity(arena.allocator(), max_display_groups),
        .indices = try .initCapacity(arena.allocator(), max_buffer_len),
        .vertices = try .initCapacity(arena.allocator(), max_buffer_len),
        .index_buffer = index_buffer,
        .vertex_buffer = vertex_buffer,
        .index_upload_buffer = index_upload_buffer,
        .vertex_upload_buffer = vertex_upload_buffer,
    };
}

pub fn deinit(self: *Self, gpu: sdl3.gpu.Device) void {
    gpu.releaseTransferBuffer(self.vertex_upload_buffer);
    gpu.releaseTransferBuffer(self.index_upload_buffer);
    gpu.releaseBuffer(self.vertex_buffer);
    gpu.releaseBuffer(self.index_buffer);
}

pub fn isEmpty(self: *const Self) bool {
    return self.display_groups.items.len == 0;
}

pub fn getDisplayGroups(self: *const Self) []const DisplayGroup {
    return self.display_groups.items;
}

pub fn getIndexBuffer(self: *const Self) sdl3.gpu.Buffer {
    return self.index_buffer;
}

pub fn getVertexBuffer(self: *const Self) sdl3.gpu.Buffer {
    return self.vertex_buffer;
}

pub fn getCycleType(self: *Self) CycleType {
    return self.frag_state.cycle_type;
}

pub fn clear(self: *Self) void {
    self.display_groups.clearRetainingCapacity();
    self.indices.clearRetainingCapacity();
    self.vertices.clearRetainingCapacity();
}

pub fn hasCapacity(self: *const Self, len: usize) bool {
    // There will always be fewer vertices than indices, so we can skip
    // checking the vertex array capacity
    return self.display_groups.items.len < max_display_groups or
        (self.indices.items.len + len) <= max_buffer_len;
}

pub fn pushTriangle(self: *Self, vertices: *const [3]Core.Vertex) void {
    const base_index = self.vertices.items.len;

    self.pushPrimitive(vertices, &.{
        @intCast(base_index),
        @intCast(base_index + 1),
        @intCast(base_index + 2),
    });
}

pub fn pushRectangle(self: *Self, vertices: *const [4]Core.Vertex) void {
    const base_index = self.vertices.items.len;

    const top_left: Core.Index = @intCast(base_index);
    const bottom_left: Core.Index = @intCast(base_index + 1);
    const top_right: Core.Index = @intCast(base_index + 2);
    const bottom_right: Core.Index = @intCast(base_index + 3);

    self.pushPrimitive(vertices, &.{
        top_left,
        bottom_left,
        top_right,
        top_right,
        bottom_left,
        bottom_right,
    });
}

pub fn setFillColor(self: *Self, fill_color: [4]f32) void {
    self.frag_state_changed = self.frag_state_changed or
        !std.meta.eql(fill_color, self.frag_state.fill_color);

    self.frag_state.fill_color = fill_color;
    fw.log.debug("Fill Color: {any}", .{fill_color});
}

pub fn setCycleType(self: *Self, cycle_type: CycleType) void {
    self.frag_state_changed = self.frag_state_changed or
        cycle_type != self.frag_state.cycle_type;

    self.frag_state.cycle_type = cycle_type;
    fw.log.debug("Cycle Type: {t}", .{cycle_type});
}

pub fn uploadBuffers(self: *Self, gpu: sdl3.gpu.Device) error{SdlError}!void {
    {
        const indices = try gpu.mapTransferBuffer(self.index_upload_buffer, true);
        defer gpu.unmapTransferBuffer(self.index_upload_buffer);

        @memcpy(
            indices[0..(@sizeOf(Core.Index) * self.indices.items.len)],
            std.mem.sliceAsBytes(self.indices.items),
        );
    }

    {
        const vertices = try gpu.mapTransferBuffer(self.vertex_upload_buffer, true);
        defer gpu.unmapTransferBuffer(self.vertex_upload_buffer);

        @memcpy(
            vertices[0..(@sizeOf(Core.Vertex) * self.vertices.items.len)],
            std.mem.sliceAsBytes(self.vertices.items),
        );
    }

    const command_buffer = try gpu.acquireCommandBuffer();

    {
        const copy_pass = command_buffer.beginCopyPass();
        defer copy_pass.end();

        copy_pass.uploadToBuffer(
            .{
                .transfer_buffer = self.index_upload_buffer,
                .offset = 0,
            },
            .{
                .buffer = self.index_buffer,
                .offset = 0,
                .size = @intCast(@sizeOf(Core.Index) * self.indices.items.len),
            },
            true,
        );

        copy_pass.uploadToBuffer(
            .{
                .transfer_buffer = self.vertex_upload_buffer,
                .offset = 0,
            },
            .{
                .buffer = self.vertex_buffer,
                .offset = 0,
                .size = @intCast(@sizeOf(Core.Vertex) * self.vertices.items.len),
            },
            true,
        );
    }

    try command_buffer.submit();
}

fn pushPrimitive(self: *Self, vertices: []const Core.Vertex, indices: []const Core.Index) void {
    self.indices.appendSliceAssumeCapacity(indices);
    self.vertices.appendSliceAssumeCapacity(vertices);

    if (!self.frag_state_changed) {
        if (self.getCurrentDisplayGroup()) |display_group| {
            display_group.len += @intCast(indices.len);
            return;
        }
    }

    self.display_groups.appendAssumeCapacity(.{
        .len = @intCast(indices.len),
        .frag_state = self.frag_state,
    });

    self.frag_state_changed = false;
}

fn getCurrentDisplayGroup(self: *Self) ?*DisplayGroup {
    if (self.display_groups.items.len == 0) {
        return null;
    }

    return &self.display_groups.items[self.display_groups.items.len - 1];
}
