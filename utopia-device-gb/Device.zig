const std = @import("std");
const fw = @import("framework");

const Cpu = fw.processor.Sm83;

const boot_rom_size = 256;
const wram_size = 8192;
const wram_mask = wram_size - 1;

pub const Args = struct {
    pub const cli = std.StaticStringMap(fw.CliArg).initComptime(.{
        .{
            "boot-rom-path", fw.CliArg{
                .desc = "Path to boot ROM",
                .type = .{ .flag = 'b' },
            },
        },
        .{
            "rom-path", fw.CliArg{
                .desc = "Path to ROM file",
                .type = .{ .positional = {} },
            },
        },
    });

    boot_rom_path: ?[]const u8,
    rom_path: []const u8,
};

const Self = @This();

cpu: Cpu,
boot_rom_enabled: bool = true,
boot_rom: *const [boot_rom_size]u8,
wram: *[wram_size]u8,
rom: []const u8,
arena: std.heap.ArenaAllocator,

pub fn init(allocator: std.mem.Allocator, args: Args) fw.InitError!fw.Device {
    var arena = std.heap.ArenaAllocator.init(allocator);

    const rom = try fw.fs.readFileAlloc(
        arena.allocator(),
        args.rom_path,
    );

    const boot_rom_path = args.boot_rom_path orelse {
        fw.log.err("Running this device without a boot ROM is not yet supported", .{});
        return error.ArgError;
    };

    const boot_rom = try fw.fs.readFileAlloc(
        arena.allocator(),
        boot_rom_path,
    );

    const wram = try arena.allocator().alloc(u8, wram_size);

    const self = try arena.allocator().create(Self);

    self.* = .{
        .cpu = .init(),
        .boot_rom = boot_rom[0..boot_rom_size],
        .wram = wram[0..wram_size],
        .rom = rom,
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
    for (0..(4_194_304 / 4 / 60)) |_| {
        self.cpu.step(.{
            .read = read,
        });

        fw.log.trace("{f}", .{self.cpu});
    }
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

fn read(cpu: *Cpu, address: u16) u8 {
    const self: *Self = @alignCast(@fieldParentPtr("cpu", cpu));

    if (address < 0x8000) {
        @branchHint(.likely);

        if (address < 0x0100 and self.boot_rom_enabled) {
            @branchHint(.unlikely);
            return self.boot_rom[address];
        } else {
            return self.rom[address & 0x7fff];
        }
    }

    if (address < 0xa000) {
        fw.log.todo("VRAM reads", .{});
    }

    if (address < 0xc000) {
        fw.log.todo("ERAM reads", .{});
    }

    if (address < 0xfe00) {
        return self.wram[address & wram_mask];
    }

    if (address >= 0xff00) {
        fw.log.todo("I/O reads", .{});
    }

    if (address < 0xfea0) {
        fw.log.todo("OAM reads", .{});
    }

    return 0;
}
