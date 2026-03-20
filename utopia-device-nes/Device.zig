const std = @import("std");
const fw = @import("framework");
const Cartridge = @import("./Cartridge.zig");
const Ppu = @import("./Ppu.zig");

const Cpu = fw.processor.Mos6502;

const wram_size = 2048;
const wram_mask = wram_size - 1;

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

cpu: Cpu,
cycles: u64 = 0,
mdr: u8 = 0,
wram: *[wram_size]u8,
ppu: Ppu,
cartridge: Cartridge,
arena: std.heap.ArenaAllocator,

pub fn init(allocator: std.mem.Allocator, args: Args) fw.InitError!fw.Device {
    var arena = std.heap.ArenaAllocator.init(allocator);

    const rom = try fw.fs.readFileAlloc(
        arena.allocator(),
        args.rom_path,
    );

    const wram = try arena.allocator().alloc(u8, wram_size);

    const self = try arena.allocator().create(Self);

    self.* = .{
        .cpu = .init(true),
        .wram = wram[0..wram_size],
        .ppu = .init(),
        .cartridge = try .init(rom),
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
    for (0..(1789773 / 60)) |_| {
        self.cpu.step(.{
            .read = read,
            .write = write,
        });

        fw.log.trace("{f} {f} T={d}", .{ self.cpu, self.ppu, self.cycles });
    }
}

fn getVideoState(self: *const Self) fw.VideoState {
    _ = self;

    const width = 256;
    const height = 240;

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

    self.cycles += 1;
    self.ppu.step();
    self.ppu.step();
    self.mdr = self.cartridge.readPrg(address, self.mdr);

    if (address < 0x2000) {
        @branchHint(.unlikely);
        self.mdr = self.wram[address & wram_mask];
    } else if (address < 0x4000) {
        @branchHint(.unlikely);
        self.mdr = self.ppu.read(address);
    } else if (address < 0x4020) {
        @branchHint(.unlikely);
        fw.log.trace("TODO: APU/Joypad reads", .{});
        self.mdr = 0;
    }

    self.step(1);

    return self.mdr;
}

fn write(cpu: *Cpu, address: u16, value: u8) void {
    const self: *Self = @alignCast(@fieldParentPtr("cpu", cpu));

    self.cycles += 1;
    self.step(3);
    self.mdr = value;
    self.cartridge.writePrg(address, value);

    if (address < 0x2000) {
        @branchHint(.unlikely);
        self.wram[address & wram_mask] = value;
    } else if (address < 0x4000) {
        @branchHint(.unlikely);
        self.ppu.write(address, value);
    } else if (address < 0x4020) {
        @branchHint(.unlikely);
        fw.log.trace("TODO: APU/Joypad writes", .{});
    }
}

fn step(self: *Self, comptime ppu_cycles: comptime_int) void {
    inline for (0..ppu_cycles) |_| {
        self.ppu.step();
    }

    // TODO: Step other components
}
