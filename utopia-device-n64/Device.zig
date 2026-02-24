const std = @import("std");
const fw = @import("framework");

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

pub fn init(args: fw.DefaultArgs, device_args: Args) !fw.Device {
    var arena = std.heap.ArenaAllocator.init(args.allocator);

    const cwd = std.fs.cwd();

    const rom = try cwd.readFileAllocOptions(
        arena.allocator(),
        device_args.rom_path,
        max_rom_size,
        null,
        .@"8",
        null,
    );

    const pifdata_path = device_args.pifdata_path orelse {
        return error.MissingPifdata;
    };

    const pifdata = try cwd.readFileAllocOptions(
        arena.allocator(),
        pifdata_path,
        pifdata_size,
        pifdata_size,
        .@"4",
        null,
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
