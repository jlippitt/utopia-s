const std = @import("std");
const fw = @import("framework");
const Cic = @import("./Cic.zig");
const Clock = @import("./Clock.zig");
const Cpu = @import("./Cpu.zig");
const Rsp = @import("./Rsp.zig");
const Rdp = @import("./Rdp.zig");
const MipsInterface = @import("./MipsInterface.zig");
const VideoInterface = @import("./VideoInterface.zig");
const AudioInterface = @import("./AudioInterface.zig");
const ParallelInterface = @import("./ParallelInterface.zig");
const RdramInterface = @import("./RdramInterface.zig");
const SerialInterface = @import("./SerialInterface.zig");

// Divide by 2 for CPU clock and by 3 for RCP clock
pub const clock_rate = 187_500_000;

pub const video_dac_rate = 1_000_000.0 * (18.0 * 227.5 / 286.0) * 17.0 / 5.0;

const max_rom_size = 1024 * 1024 * 1024; // 1GiB
const rdram_size = 8 * 1024 * 1024; // 8MiB
const systest_output_size = 512;

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

const Page = enum {
    rdram_registers,
    rsp,
    rdp_command,
    rdp_span,
    mips_interface,
    video_interface,
    audio_interface,
    parallel_interface,
    rdram_interface,
    serial_interface,
    dd_registers,
    dd_ipl_rom,
    cartridge_sram,
    cartridge_rom,
    pifdata,
    unmapped,
};

const memory_map: [512]Page = blk: {
    var pages: [512]Page = @splat(.unmapped);
    pages[0x03f] = .rdram_registers;
    pages[0x040] = .rsp;
    pages[0x041] = .rdp_command;
    pages[0x042] = .rdp_span;
    pages[0x043] = .mips_interface;
    pages[0x044] = .video_interface;
    pages[0x045] = .audio_interface;
    pages[0x046] = .parallel_interface;
    pages[0x047] = .rdram_interface;
    pages[0x048] = .serial_interface;
    @memset(pages[0x050..0x060], .dd_registers);
    @memset(pages[0x060..0x080], .dd_ipl_rom);
    @memset(pages[0x080..0x100], .cartridge_sram);
    @memset(pages[0x100..0x1fc], .cartridge_rom);
    pages[0x1fc] = .pifdata;
    break :blk pages;
};

const Self = @This();

cpu: Cpu,
clock: Clock,
rdram: *align(4) [rdram_size]u8,
rsp: Rsp,
rdp: Rdp,
mi: MipsInterface,
vi: VideoInterface,
ai: AudioInterface,
pi: ParallelInterface,
ri: RdramInterface,
si: SerialInterface,
systest_output: *[systest_output_size]u8,
arena: std.heap.ArenaAllocator,

// utopia.Device methods

pub fn init(allocator: std.mem.Allocator, device_args: Args) fw.InitError!fw.Device {
    var arena = std.heap.ArenaAllocator.init(allocator);

    const rom = try fw.fs.readFileAllocAligned(
        arena.allocator(),
        device_args.rom_path,
        .@"8",
    );

    const pifdata_path = device_args.pifdata_path orelse {
        fw.log.err("Running this device without a 'pifdata' ROM is not yet supported", .{});
        return error.ArgError;
    };

    const pifdata = try fw.fs.readFileAllocAligned(
        arena.allocator(),
        pifdata_path,
        .@"4",
    );

    const rdram = try arena.allocator().alignedAlloc(u8, .@"4", rdram_size);

    const cic = Cic.init(rom[0x0040..0x1000]);

    if (cic.getRamSizeAddress()) |address| {
        fw.mem.writeBe(u32, rdram, address, rdram_size);
    }

    const systest_output = try arena.allocator().alloc(u8, systest_output_size);

    var clock = Clock.init();
    const vi = try VideoInterface.init(&arena, &clock);
    const ai = AudioInterface.init(&clock);

    const self = try arena.allocator().create(Self);

    self.* = .{
        .cpu = .init(),
        .clock = clock,
        .rdram = rdram[0..rdram_size],
        .rsp = try .init(&arena),
        .rdp = try .init(&arena),
        .mi = .init(),
        .vi = vi,
        .ai = ai,
        .pi = .init(rom),
        .ri = .init(),
        .si = .init(pifdata, cic.getSeed()),
        .systest_output = systest_output[0..systest_output_size],
        .arena = arena,
    };

    return fw.Device.init(self, .{
        .deinit = deinit,
        .runFrame = runFrame,
        .getScreenSize = getScreenSize,
        .getPixels = getPixels,
        .updateControllerState = updateControllerState,
    });
}

pub fn deinit(self: *Self) void {
    self.rdp.deinit();
    self.arena.deinit();
}

pub fn runFrame(self: *Self) fw.RenderError!void {
    while (true) {
        self.cpu.step();
        self.rsp.step();

        self.clock.addCycles(4);

        while (self.clock.nextEvent()) |event| {
            @branchHint(.unlikely);

            switch (event) {
                .cpu_interrupt => self.cpu.handleInterruptEvent(),
                .cpu_timer => self.cpu.handleTimerEvent(),
                .rdp_dma => try self.rdp.handleDmaEvent(),
                .ai_sample => self.ai.handleSampleEvent(),
                .vi_new_line => if (try self.vi.handleNewLineEvent()) {
                    return;
                },
            }
        }
    }
}

pub fn getScreenSize(self: *const Self) fw.ScreenSize {
    return self.vi.getScreenSize();
}

pub fn getPixels(self: *const Self) []const u8 {
    return self.vi.getPixels();
}

pub fn updateControllerState(self: *Self, state: *const fw.ControllerState) void {
    self.si.updateControllerState(state);
}

// CPU methods

pub fn read(self: *Self, address: u32) u32 {
    if (address < rdram_size) {
        return fw.mem.readBe(u32, self.rdram, address & 0xffff_fffc);
    }

    const page_index = address >> 20;

    if (page_index >= memory_map.len) {
        @branchHint(.unlikely);
        fw.log.unimplemented("64-bit addressing", .{});
    }

    return switch (memory_map[page_index]) {
        .rsp => self.rsp.read(address),
        .rdp_command => self.rdp.readCommand(address),
        .mips_interface => self.mi.read(address),
        .video_interface => self.vi.read(address),
        .audio_interface => self.ai.read(address),
        .parallel_interface => self.pi.read(address),
        .rdram_interface => self.ri.read(address),
        .serial_interface => self.si.read(address),
        .dd_registers => std.math.maxInt(u32), // TODO
        .dd_ipl_rom => 0, // TODO
        .cartridge_rom => self.pi.readRom(address),
        .pifdata => self.si.readPif(address),
        .unmapped => blk: {
            fw.log.warn("Read from unmapped address: {X:08}", .{address});
            break :blk 0;
        },
        else => |page| fw.log.todo("Read from memory page: {t}", .{page}),
    };
}

pub fn write(self: *Self, address: u32, value: u32, mask: u32) void {
    if (address < rdram_size) {
        fw.mem.writeMaskedBe(u32, self.rdram, address & 0xffff_fffc, value, mask);
        return;
    }

    const page_index = address >> 20;

    if (page_index >= memory_map.len) {
        @branchHint(.unlikely);
        fw.log.unimplemented("64-bit addressing", .{});
    }

    switch (memory_map[page_index]) {
        .rsp => self.rsp.write(address, value, mask),
        .rdp_command => self.rdp.writeCommand(address, value, mask),
        .mips_interface => self.mi.write(address, value, mask),
        .video_interface => self.vi.write(address, value, mask),
        .audio_interface => self.ai.write(address, value, mask),
        .parallel_interface => self.pi.write(address, value, mask),
        .rdram_interface => self.ri.write(address, value, mask),
        .serial_interface => self.si.write(address, value, mask),
        .dd_registers => {}, // TODO
        .dd_ipl_rom => {}, // TODO
        .cartridge_rom => switch (address) {
            // Console output for n64-systemtest
            0x13ff_0020...0x13ff_021f => fw.mem.writeMaskedBe(
                u32,
                self.systest_output,
                address - 0x13ff_0020,
                value,
                mask,
            ),
            0x13ff_0014 => {
                _ = std.fs.File.stderr().write(self.systest_output[0..(value & mask)]) catch {};
            },
            else => fw.log.warn("Write to cartridge ROM: {X:08} <= {X:08}", .{ address, value }),
        },
        .pifdata => self.si.writePif(address, value, mask),
        .unmapped => fw.log.warn("Write to unmapped address: {X:08} <= {X:08}", .{
            address,
            value,
        }),
        else => |page| fw.log.todo("Write to memory page: {t}", .{page}),
    }
}
