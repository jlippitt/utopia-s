const std = @import("std");
const fw = @import("framework");
const log = fw.log;

const max_rom_size = 1024 * 1024 * 1024; // 1GiB
const pifdata_size = 2048;

pub const Args = struct {
    pub const cli = std.StaticStringMap(fw.CliArg).initComptime(.{
        .{
            "pifdata-path", fw.CliArg{
                .desc = "Path to PIFDATA bios file",
                .type = .{ .flag = 'p' },
            },
        },
        .{
            "rom-path", fw.CliArg{
                .desc = "Path to ROM file",
                .type = .{ .positional = {} },
            },
        },
    });

    pifdata_path: ?[]const u8,
    rom_path: []const u8,
};

const Self = @This();

rom: []align(8) const u8,
pifdata: *align(4) [pifdata_size]u8,
arena: std.heap.ArenaAllocator,

pub fn init(allocator: std.mem.Allocator, device_args: Args) fw.DeviceError!fw.Device {
    var arena = std.heap.ArenaAllocator.init(allocator);

    const rom = try fw.fs.readFileAllocAligned(
        arena.allocator(),
        device_args.rom_path,
        .@"8",
    );

    const pifdata_path = device_args.pifdata_path orelse {
        log.err("Running this device without a 'pifdata' ROM is not yet supported", .{});
        return error.ArgError;
    };

    const pifdata = try fw.fs.readFileAllocAligned(
        arena.allocator(),
        pifdata_path,
        .@"4",
    );

    const self = try arena.allocator().create(Self);

    self.* = .{
        .rom = rom,
        .pifdata = pifdata[0..pifdata_size],
        .arena = arena,
    };

    return fw.Device.init(self, .{
        .deinit = deinit,
        .runFrame = runFrame,
    });
}

pub fn deinit(self: *Self) void {
    self.arena.deinit();
}

pub fn runFrame(self: *Self) void {
    _ = self;
    std.debug.print("Running frame...\n", .{});
}
