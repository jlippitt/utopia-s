const std = @import("std");
const fw = @import("framework");
const processor = @import("processor");
const Cartridge = @import("./Cartridge.zig");

const ram_size = 8192;
const ram_mask = ram_size - 1;

const Cpu = processor.Z80;

pub const Args = struct {};

const Self = @This();

cpu: Cpu,
mem_ctrl: MemoryControl = .{},
mdr: u8 = 0,
cycles: u64 = 0,
ram: *[ram_size]u8,
cartridge: Cartridge,

pub fn init(arena: *std.heap.ArenaAllocator, vfs: fw.Vfs, args: Args) fw.InitError!fw.Device {
    _ = args;

    const ram = try arena.allocator().alloc(u8, ram_size);

    const self = try arena.allocator().create(Self);

    self.* = .{
        .cpu = .init(),
        .ram = ram[0..ram_size],
        .cartridge = try .init(arena, vfs),
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
            .idle = idle,
            .fetch = fetch,
            .read = read,
            .write = write,
        });

        fw.log.trace("{f} T={d}", .{ self.cpu, self.cycles });
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

fn idle(cpu: *Cpu, cycles: u64) void {
    const self: *Self = @alignCast(@fieldParentPtr("cpu", cpu));
    self.cycles += cycles;
}

fn fetch(cpu: *Cpu, address: u16) u8 {
    const self: *Self = @alignCast(@fieldParentPtr("cpu", cpu));
    self.cycles += 4;
    return self.readInner(address);
}

fn read(cpu: *Cpu, address: u16) u8 {
    const self: *Self = @alignCast(@fieldParentPtr("cpu", cpu));
    self.cycles += 3;
    return self.readInner(address);
}

fn readInner(self: *Self, address: u16) u8 {
    self.mdr = self.cartridge.read(address, self.mdr);

    if (address >= 0xc000 and !self.mem_ctrl.ram_disable) {
        self.mdr = self.ram[address & ram_mask];
    }

    return self.mdr;
}

fn write(cpu: *Cpu, address: u16, value: u8) void {
    const self: *Self = @alignCast(@fieldParentPtr("cpu", cpu));
    self.cycles += 3;
    self.mdr = value;

    self.cartridge.write(address, value);

    if (address >= 0xc000 and !self.mem_ctrl.ram_disable) {
        self.ram[address & ram_mask] = value;
    }
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
