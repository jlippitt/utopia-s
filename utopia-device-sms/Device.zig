const std = @import("std");
const fw = @import("framework");
const processor = @import("processor");

const ram_size = 8192;
const ram_mask = ram_size - 1;

const Cpu = processor.Z80;

pub const Args = struct {};

const Self = @This();

cpu: Cpu,
mem_ctrl: MemoryControl = .{},
ram: *[ram_size]u8,
rom: []const u8,

pub fn init(arena: *std.heap.ArenaAllocator, vfs: fw.Vfs, args: Args) fw.InitError!fw.Device {
    _ = args;

    const rom = try vfs.readRom(arena.allocator());
    const ram = try arena.allocator().alloc(u8, ram_size);

    const self = try arena.allocator().create(Self);

    self.* = .{
        .cpu = .init(),
        .ram = ram[0..ram_size],
        .rom = rom,
    };

    return .init(self, .{
        .deinit = deinit,
        .runFrame = runFrame,
        .getVideoState = getVideoState,
        .getAudioState = getAudioState,
        .updateControllerState = updateControllerState,
        .save = save,
    });
}

fn deinit(self: *Self) void {
    _ = self;
}

fn runFrame(self: *Self) void {
    for (0..(3579540 / 60 / 4)) |_| {
        self.cpu.step(.{
            .fetch = fetch,
        });

        fw.log.trace("{f}", .{self.cpu});
    }
}

fn getVideoState(self: *const Self) fw.VideoState {
    _ = self;

    const width = 256;
    const height = 192;

    return .{
        .resolution = .{ .x = width, .y = height },
        .scale_mode = .integer,
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

fn save(self: *Self, allocator: std.mem.Allocator, vfs: fw.Vfs) fw.Vfs.Error!void {
    _ = self;
    _ = allocator;
    _ = vfs;
}

fn fetch(cpu: *Cpu, address: u16) u8 {
    const self: *Self = @alignCast(@fieldParentPtr("cpu", cpu));

    if (address >= 0xc000 and !self.mem_ctrl.ram_disable) {
        return self.ram[address & ram_mask];
    }

    return self.rom[address];
}

const MemoryControl = packed struct(u8) {
    __: u2 = 0,
    io_disable: bool = false,
    bios_disable: bool = false,
    ram_disable: bool = false,
    card_disable: bool = false,
    cartridge_disable: bool = false,
    expansion_disable: bool = false,
};
