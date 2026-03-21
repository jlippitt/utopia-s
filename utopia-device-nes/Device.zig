const std = @import("std");
const fw = @import("framework");
const processor = @import("processor");
const Cartridge = @import("./Cartridge.zig");
const Apu = @import("./Apu.zig");
const Joypad = @import("./Joypad.zig");
const Ppu = @import("./Ppu.zig");

const Cpu = processor.Mos6502;

const wram_size = 2048;
const wram_mask = wram_size - 1;

pub const Args = struct {};

const Self = @This();

cpu: Cpu,
dma: Dma = .{},
cycles: u64 = 0,
mdr: u8 = 0,
wram: *[wram_size]u8,
ppu: Ppu,
apu: Apu,
joypad: Joypad,
cartridge: Cartridge,

pub fn init(arena: *std.heap.ArenaAllocator, vfs: anytype, args: Args) fw.InitError!fw.Device {
    _ = args;

    const rom = try vfs.readRom(arena);
    const wram = try arena.allocator().alloc(u8, wram_size);

    const self = try arena.allocator().create(Self);

    self.* = .{
        .cpu = .init(true),
        .wram = wram[0..wram_size],
        .ppu = try .init(arena),
        .apu = try .init(arena),
        .joypad = .init(),
        .cartridge = try .init(arena, rom),
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
    _ = self;
}

fn runFrame(self: *Self) void {
    self.apu.clearSampleBuffer();
    self.ppu.beginFrame();

    while (!self.ppu.frameDone()) {
        self.cpu.step(.{
            .read = read,
            .write = write,
        });

        fw.log.trace("{f} {f} T={d}", .{ self.cpu, self.ppu, self.cycles });
    }
}

fn getVideoState(self: *const Self) fw.VideoState {
    return self.ppu.getVideoState();
}

fn getAudioState(self: *const Self) fw.AudioState {
    return self.apu.getAudioState();
}

fn updateControllerState(self: *Self, state: *const fw.ControllerState) void {
    self.joypad.update(state);
}

fn read(cpu: *Cpu, address: u16) u8 {
    const self: *Self = @alignCast(@fieldParentPtr("cpu", cpu));

    if (@as(u2, @bitCast(self.dma.request)) != 0) {
        self.transferDma();
    }

    return self.readInner(address);
}

fn readInner(self: *Self, address: u16) u8 {
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

        if ((address & 0xfffe) == 0x4016) {
            self.mdr = self.joypad.read(address, self.mdr);
        } else {
            fw.log.trace("TODO: APU reads", .{});
            self.mdr = 0;
        }
    }

    self.step(1);

    return self.mdr;
}

fn write(cpu: *Cpu, address: u16, value: u8) void {
    const self: *Self = @alignCast(@fieldParentPtr("cpu", cpu));

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

        if (address == 0x4014) {
            self.dma.request.oam = true;
            self.dma.oam_page = value;
        } else if (address == 0x4016) {
            self.joypad.write(value);
        } else {
            fw.log.trace("TODO: APU writes", .{});
        }
    }
}

fn transferDma(self: *Self) void {
    fw.log.trace("DMA Transfer Begin", .{});
    defer fw.log.trace("DMA Transfer End", .{});

    self.step(3);

    if ((self.cycles & 1) != 0) {
        self.step(3);
    }

    if (!self.dma.request.oam) {
        fw.log.todo("DMC", .{});
    }

    self.dma.request.oam = false;

    const oam_base = @as(u16, self.dma.oam_page) << 8;

    for (0..256) |index| {
        // TODO: DMC
        const address = oam_base | @as(u8, @intCast(index));
        const value = self.readInner(address);
        fw.log.trace("DMA Write: OAM <= {X:02} <= {X:04}", .{ value, address });
        self.step(3);
        self.ppu.writeOam(value);
    }
}

fn step(self: *Self, comptime ppu_cycles: comptime_int) void {
    self.cycles += 1;

    inline for (0..ppu_cycles) |_| {
        self.ppu.step();
    }

    self.apu.step();
}

const DmaRequest = packed struct(u2) {
    oam: bool = false,
    dmc: bool = false,
};

const Dma = struct {
    request: DmaRequest = .{},
    oam_page: u8 = 0,
};
