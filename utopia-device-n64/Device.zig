const std = @import("std");
const fw = @import("framework");
const Cic = @import("./Cic.zig");
const Cpu = @import("./Cpu.zig");
const Rsp = @import("./Rsp.zig");
const Rdp = @import("./Rdp.zig");
const ParallelInterface = @import("./ParallelInterface.zig");
const RdramInterface = @import("./RdramInterface.zig");
const SerialInterface = @import("./SerialInterface.zig");

const max_rom_size = 1024 * 1024 * 1024; // 1GiB
const rdram_size = 8 * 1024 * 1024; // 8MiB

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
    var pages: [512]Page = undefined;
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
rdram: *align(4) [rdram_size]u8,
rsp: Rsp,
rdp: Rdp,
pi: ParallelInterface,
ri: RdramInterface,
si: SerialInterface,
arena: std.heap.ArenaAllocator,

pub fn init(allocator: std.mem.Allocator, device_args: Args) fw.DeviceError!fw.Device {
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

    const self = try arena.allocator().create(Self);

    self.* = .{
        .cpu = .init(),
        .rdram = rdram[0..rdram_size],
        .rsp = try .init(arena.allocator()),
        .rdp = .init(),
        .pi = .init(rom),
        .ri = .init(),
        .si = .init(pifdata, cic.getSeed()),
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
    while (true) {
        self.cpu.step(.{
            .read = read,
            .write = write,
        });
    }
}

fn read(core: *Cpu, address: u32) u32 {
    const self: *Self = @alignCast(@fieldParentPtr("cpu", core));

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
        .parallel_interface => self.pi.read(address),
        .rdram_interface => self.ri.read(address),
        .serial_interface => self.si.read(address),
        .dd_registers => std.math.maxInt(u32), // TODO
        .dd_ipl_rom => 0, // TODO
        .cartridge_rom => self.pi.readRom(address),
        .pifdata => self.si.readPif(address),
        else => |page| fw.log.todo("Read from memory page: {t}", .{page}),
    };
}

fn write(core: *Cpu, address: u32, value: u32, mask: u32) void {
    const self: *Self = @alignCast(@fieldParentPtr("cpu", core));

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
        .video_interface => {}, // TODO
        .audio_interface => {}, // TODO
        .parallel_interface => self.pi.write(address, value, mask),
        .rdram_interface => self.ri.write(address, value, mask),
        .serial_interface => self.si.write(address, value, mask),
        .dd_registers => {}, // TODO
        .dd_ipl_rom => {}, // TODO
        .pifdata => self.si.writePif(address, value, mask),
        else => |page| fw.log.todo("Write to memory page: {t}", .{page}),
    }
}
