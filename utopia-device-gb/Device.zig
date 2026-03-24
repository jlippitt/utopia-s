const std = @import("std");
const fw = @import("framework");
const processor = @import("processor");
const Gpu = @import("./Gpu.zig");
const Interrupt = @import("./Interrupt.zig");

const Cpu = processor.Sm83;

const boot_rom_size = 256;
const wram_size = 8192;
const wram_mask = wram_size - 1;
const hram_size = 127;
const hram_mask = hram_size;

const m_cycle = 4;

var test_rom_buf: [256]u8 = undefined;
var test_rom_writer = std.fs.File.stderr().writer(&test_rom_buf);

pub const Args = struct {};

const Self = @This();

cpu: Cpu,
cycles: u64 = 0,
interrupt: Interrupt,
dma_active: bool = false,
dma_address: u16 = 0,
boot_rom_enable: bool = true,
boot_rom: *const [boot_rom_size]u8,
wram: *[wram_size]u8,
hram: *[hram_size]u8,
gpu: Gpu,
rom: []const u8,

pub fn init(arena: *std.heap.ArenaAllocator, vfs: fw.Vfs, args: Args) fw.InitError!fw.Device {
    _ = args;

    const rom = try vfs.readRom(arena.allocator());
    const boot_rom = try vfs.readBios(arena.allocator(), "dmg_boot.bin");

    const wram = try arena.allocator().alloc(u8, wram_size);
    const hram = try arena.allocator().alloc(u8, hram_size);

    const self = try arena.allocator().create(Self);

    self.* = .{
        .cpu = .init(),
        .interrupt = .init(),
        .boot_rom = boot_rom[0..boot_rom_size],
        .wram = wram[0..wram_size],
        .hram = hram[0..hram_size],
        .gpu = try .init(arena),
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
    self.gpu.beginFrame();

    while (!self.gpu.frameDone()) {
        self.cpu.step(.{
            .idle = idle,
            .read = read,
            .write = write,
            .readIo = readIo,
            .writeIo = writeIo,
            .clearInterrupt = clearInterrupt,
        });

        fw.log.trace("{f} {f} T={d}", .{ self.cpu, self.gpu, self.cycles });
    }
}

pub fn getVideoState(self: *const Self) fw.VideoState {
    return self.gpu.getVideoState();
}

pub fn getAudioState(self: *const Self) fw.AudioState {
    _ = self;

    return .{
        .sample_rate = fw.default_sample_rate,
        .sample_data = &.{},
    };
}

pub fn updateControllerState(self: *Self, state: *const fw.ControllerState) void {
    _ = self;
    _ = state;
}

pub fn save(self: *Self, allocator: std.mem.Allocator, vfs: fw.Vfs) fw.Vfs.Error!void {
    _ = self;
    _ = allocator;
    _ = vfs;
}

pub fn requestOamDma(self: *Self, address: u8) void {
    self.dma_active = true;
    self.dma_address = @as(u16, address) << 8;
    fw.log.trace("DMA Transfer Begin", .{});
}

fn idle(cpu: *Cpu) void {
    const self: *Self = @alignCast(@fieldParentPtr("cpu", cpu));
    self.step();

    if (self.dma_active) {
        @branchHint(.unlikely);
        self.transferDma();
    }
}

fn read(cpu: *Cpu, address: u16) u8 {
    const self: *Self = @alignCast(@fieldParentPtr("cpu", cpu));
    self.step();

    if (self.dma_active) {
        @branchHint(.unlikely);
        self.transferDma();
        return self.readRestricted(address);
    }

    return self.readNormal(address);
}

fn readRestricted(self: *Self, address: u16) u8 {
    if (address >= 0xff00) {
        return self.readIoRestricted(@truncate(address));
    }

    return 0xff;
}

fn readNormal(self: *Self, address: u16) u8 {
    if (address < 0x8000) {
        @branchHint(.likely);

        if (address < 0x0100 and self.boot_rom_enable) {
            @branchHint(.unlikely);
            return self.boot_rom[address];
        } else {
            return self.rom[address & 0x7fff];
        }
    }

    if (address < 0xa000) {
        return self.gpu.readVram(address);
    }

    if (address < 0xc000) {
        fw.log.todo("ERAM reads", .{});
    }

    if (address < 0xfe00) {
        return self.wram[address & wram_mask];
    }

    if (address >= 0xff00) {
        return self.readIoNormal(@truncate(address));
    }

    if (address < 0xfea0) {
        return self.gpu.readOam(@truncate(address));
    }

    return 0;
}

fn write(cpu: *Cpu, address: u16, value: u8) void {
    const self: *Self = @alignCast(@fieldParentPtr("cpu", cpu));
    self.step();

    if (self.dma_active) {
        @branchHint(.unlikely);
        self.transferDma();
        self.writeRestricted(address, value);
        return;
    }

    self.writeNormal(address, value);
}

fn writeRestricted(self: *Self, address: u16, value: u8) void {
    if (address >= 0xff00) {
        self.writeIoRestricted(@truncate(address), value);
        return;
    }
}

fn writeNormal(self: *Self, address: u16, value: u8) void {
    if (address < 0x8000) {
        @branchHint(.unlikely);
        fw.log.warn("TODO: Mapper writes", .{});
    }

    if (address < 0xa000) {
        self.gpu.writeVram(address, value);
        return;
    }

    if (address < 0xc000) {
        fw.log.todo("ERAM writes", .{});
    }

    if (address < 0xfe00) {
        self.wram[address & wram_mask] = value;
        return;
    }

    if (address >= 0xff00) {
        self.writeIoNormal(@truncate(address), value);
        return;
    }

    if (address < 0xfea0) {
        self.gpu.writeOam(@truncate(address), value);
        return;
    }
}

fn readIo(cpu: *Cpu, address: u8) u8 {
    const self: *Self = @alignCast(@fieldParentPtr("cpu", cpu));
    self.step();

    if (self.dma_active) {
        @branchHint(.unlikely);
        self.transferDma();
        return self.readIoRestricted(address);
    }

    return self.readIoNormal(address);
}

fn readIoRestricted(self: *Self, address: u8) u8 {
    if (address >= 0x80 and address <= 0xfe) {
        return self.hram[address & hram_mask];
    }

    return 0xff;
}

fn readIoNormal(self: *Self, address: u8) u8 {
    return switch (address) {
        0x00 => 0xff, // TODO: Joypad,
        0x01, 0x02 => 0, // TODO: Serial port
        0x04...0x07 => 0, // TODO: Timer
        0x0f => self.interrupt.getFlags(),
        0x10...0x3f => 0, // TODO: APU
        0x40...0x4f => self.gpu.read(address),
        0x80...0xfe => self.hram[address & hram_mask],
        0xff => self.interrupt.getEnable(),
        else => fw.log.todo("I/O read: {X:02}", .{address}),
    };
}

fn writeIo(cpu: *Cpu, address: u8, value: u8) void {
    const self: *Self = @alignCast(@fieldParentPtr("cpu", cpu));
    self.step();

    if (self.dma_active) {
        @branchHint(.unlikely);
        self.transferDma();
        return self.writeIoRestricted(address, value);
    }

    self.writeIoNormal(address, value);
}

fn writeIoRestricted(self: *Self, address: u8, value: u8) void {
    if (address >= 0x80 and address <= 0xfe) {
        self.hram[address & hram_mask] = value;
        return;
    }
}

fn writeIoNormal(self: *Self, address: u8, value: u8) void {
    switch (address) {
        0x00 => {}, // TODO: Joypad
        0x01 => {
            // TODO: Serial port
            test_rom_writer.interface.writeByte(value) catch {};
        },
        0x02 => if (value == 0x81) {
            // TODO: Serial port
            test_rom_writer.interface.flush() catch {};
        },
        0x04...0x07 => {}, // TODO: Timer
        0x0f => self.interrupt.setFlags(value),
        0x10...0x3f => {}, // TODO: APU
        0x40...0x4f => self.gpu.write(address, value),
        0x50 => {
            self.boot_rom_enable = false;
            fw.log.debug("Boot ROM Enable: {}", .{self.boot_rom_enable});
        },
        0x80...0xfe => self.hram[address & hram_mask] = value,
        0xff => self.interrupt.setEnable(value),
        else => fw.log.warn("TODO: I/O write: {X:02} <= {X:02}", .{ address, value }),
    }
}

fn clearInterrupt(cpu: *Cpu, interrupt: u5) void {
    const self: *Self = @alignCast(@fieldParentPtr("cpu", cpu));
    self.interrupt.clear(@enumFromInt(interrupt));
}

fn step(self: *Self) void {
    self.cycles += m_cycle;
    self.gpu.step(m_cycle);
}

fn transferDma(self: *Self) void {
    const oam_address: u8 = @truncate(self.dma_address);
    const value = self.readNormal(self.dma_address);

    fw.log.trace("DMA Transfer: OAM:{X:02} <= {X:02} <= {X:04}", .{
        oam_address,
        value,
        self.dma_address,
    });

    self.gpu.writeOam(oam_address, value);
    self.dma_address +%= 1;

    if ((self.dma_address & 0xff) == 0xa0) {
        self.dma_active = false;
        fw.log.trace("DMA Transfer End", .{});
    }
}
