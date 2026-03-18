const std = @import("std");
const fw = @import("framework");

pub const Args = struct {
    pub const cli = std.StaticStringMap(fw.CliArg).initComptime(.{
        .{
            "rom-path", fw.CliArg{
                .desc = "Path to ROM file",
                .type = .{ .positional = {} },
            },
        },
    });

    rom_path: []const u8,
};

const Self = @This();

arena: std.heap.ArenaAllocator,

pub fn init(allocator: std.mem.Allocator, args: Args) fw.InitError!fw.Device {
    var arena = std.heap.ArenaAllocator.init(allocator);

    const rom = try fw.fs.readFileAlloc(
        arena.allocator(),
        args.rom_path,
    );

    _ = rom;

    const self = try arena.allocator().create(Self);

    self.* = .{
        .arena = arena,
    };

    return fw.Device.init(self, .{
        .deinit = deinit,
        .runFrame = runFrame,
        .getVideoState = getVideoState,
        .getAudioState = getAudioState,
        .updateControllerState = updateControllerState,
    });
}

fn deinit(self: *Self) void {
    self.arena.deinit();
}

fn runFrame(self: *Self) void {
    _ = self;
}

fn getVideoState(self: *const Self) fw.VideoState {
    _ = self;

    const width = 160;
    const height = 144;

    return .{
        .resolution = .{ .x = width, .y = height },
        .pixel_data = &[1]u8{0} ** (width * height * 4),
    };
}

fn getAudioState(self: *const Self) fw.AudioState {
    _ = self;

    return .{
        .sample_rate = fw.default_sample_rate,
        .sample_data = &.{},
    };
}

fn updateControllerState(self: *Self, state: *const fw.ControllerState) void {
    _ = self;
    _ = state;
}
