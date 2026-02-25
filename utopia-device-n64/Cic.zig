const std = @import("std");
const fw = @import("framework");

const Self = @This();

const ChipType = enum {
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

chip_type: ChipType,

pub fn init(ipl3: []align(8) const u8) Self {
    // Use checksum of IPL3 to determine the CIC type
    const checksum = std.hash.crc.Crc32Cksum.hash(ipl3);

    const chip_type: ChipType = switch (checksum) {
        0x0013_579c => .nus_6101,
        0xd1f2_d592 => .nus_6102,
        0x27df_61e2 => .nus_6103,
        0x229f_516c => .nus_6105,
        0xa0dd_69f7 => .nus_6106,
        0x522f_d8eb => .mini_ipl3,
        else => blk: {
            fw.log.warn("No known CIC type for IPL3 checksum {X:08}. Defaulting to NUS-6102.", .{
                checksum,
            });

            break :blk .nus_6102;
        },
    };

    fw.log.debug("CIC Type: {f}", .{chip_type});

    return .{
        .chip_type = chip_type,
    };
}

pub fn getSeed(self: *const Self) u32 {
    return switch (self.chip_type) {
        .nus_6101 => 0x0004_3f3f,
        .nus_6102, .mini_ipl3 => 0x0000_3f3f,
        .nus_6103 => 0x0000_783f,
        .nus_6105 => 0x0000_913f,
        .nus_6106 => 0x0000_853f,
    };
}

pub fn getRamSizeAddress(self: *const Self) ?u32 {
    return switch (self.chip_type) {
        .nus_6101, .nus_6102, .mini_ipl3 => 0x0000_0318,
        .nus_6105 => 0x0000_03f0,
        else => null,
    };
}
