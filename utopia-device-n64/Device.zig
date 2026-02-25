const std = @import("std");
const fw = @import("framework");
const Cpu = @import("./Cpu.zig");
const Rsp = @import("./Rsp.zig");
const Rdp = @import("./Rdp.zig");
const ParallelInterface = @import("./ParallelInterface.zig");
const SerialInterface = @import("./SerialInterface.zig");

const max_rom_size = 1024 * 1024 * 1024; // 1GiB

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

pub const CicType = enum {
    nus_6101,
    nus_6102,
    nus_6103,
    nus_6105,
    nus_6106,
    mini_ipl3,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        _ = try writer.write(switch (self) {
            .nus_6101 => "NUS-6101",
            .nus_6102 => "NUS-6102",
            .nus_6103 => "NUS-6103",
            .nus_6105 => "NUS-6105",
            .nus_6106 => "NUS-6106",
            .mini_ipl3 => "Mini-IPL3",
        });
    }
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
rsp: Rsp,
rdp: Rdp,
pi: ParallelInterface,
si: SerialInterface,
rom: []align(8) const u8,
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

    // Use checksum of IPL3 to determine the CIC type
    const ipl3_checksum = std.hash.crc.Crc32Cksum.hash(rom[0x0040..0x1000]);

    const cic_type: CicType = switch (ipl3_checksum) {
        0x0013_579c => .nus_6101,
        0xd1f2_d592 => .nus_6102,
        0x27df_61e2 => .nus_6103,
        0x229f_516c => .nus_6105,
        0xa0dd_69f7 => .nus_6106,
        0x522f_d8eb => .mini_ipl3,
        else => blk: {
            fw.log.warn("No known CIC type for IPL3 checksum {X:08}. Defaulting to NUS-6102.", .{
                ipl3_checksum,
            });

            break :blk .nus_6102;
        },
    };

    fw.log.debug("CIC Type: {f}", .{cic_type});

    // Determine 'magic' CIC seed value that should be written to PIF RAM
    const cic_seed: u32 = switch (cic_type) {
        .nus_6101 => 0x0004_3f3f,
        .nus_6102, .mini_ipl3 => 0x0000_3f3f,
        .nus_6103 => 0x0000_783f,
        .nus_6105 => 0x0000_913f,
        .nus_6106 => 0x0000_853f,
    };

    const self = try arena.allocator().create(Self);

    self.* = .{
        .cpu = .init(),
        .rsp = try .init(arena.allocator()),
        .rdp = .init(),
        .pi = .init(),
        .si = .init(pifdata, cic_seed),
        .rom = rom,
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

    const page_index = address >> 20;

    if (page_index >= memory_map.len) {
        @branchHint(.unlikely);
        fw.log.unimplemented("64-bit addressing", .{});
    }

    return switch (memory_map[page_index]) {
        .rsp => self.rsp.read(address),
        .rdp_command => self.rdp.readCommand(address),
        .parallel_interface => self.pi.read(address),
        .serial_interface => self.si.read(address),
        .dd_registers => std.math.maxInt(u32), // TODO
        .dd_ipl_rom => 0, // TODO
        .pifdata => self.si.readPif(address),
        else => |page| fw.log.todo("Read from memory page: {t}", .{page}),
    };
}

fn write(core: *Cpu, address: u32, value: u32, mask: u32) void {
    const self: *Self = @alignCast(@fieldParentPtr("cpu", core));

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
        .serial_interface => self.si.write(address, value, mask),
        .dd_registers => {}, // TODO
        .dd_ipl_rom => {}, // TODO
        .pifdata => self.si.writePif(address, value, mask),
        else => |page| fw.log.todo("Write to memory page: {t}", .{page}),
    }
}
