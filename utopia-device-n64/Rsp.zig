const std = @import("std");
const fw = @import("framework");
const Device = @import("./Device.zig");
const register = @import("./register.zig");
const Core = @import("./Rsp/Core.zig");

const mem_size = 8192;
const bank_size = mem_size / 2;

const Self = @This();

core: Core,
mem: *align(16) [mem_size]u8,
sp_addr: u13 = 0,
dram_addr: u24 = 0,
dma: Dma = .{},
status: Status = .{},
semaphore: bool = false,

pub fn init(arena: *std.heap.ArenaAllocator) !Self {
    const mem = try arena.allocator().alignedAlloc(u8, .@"16", mem_size);

    return .{
        .core = .init(),
        .mem = mem[0..mem_size],
    };
}

// External-facing interface

pub fn getDmemConst(self: *const Self) *align(16) const [bank_size]u8 {
    return self.mem[bank_size..][0..bank_size];
}

pub fn step(self: *Self) void {
    if (self.status.halted) {
        return;
    }

    self.core.step();
    self.status.halted = self.status.halted or self.status.sstep;
}

pub fn read(self: *Self, address: u32) u32 {
    if ((address & 0x000c_0000) == 0) {
        return fw.mem.readBe(u32, self.mem, address & 0x1ffc);
    }

    if ((address & 0x000c_0000) == 0x0004_0000) {
        return self.readRegister(@truncate(address >> 2));
    }

    if ((address & 0x000f_ffff) == 0x0008_0000) {
        return self.core.readPc();
    }

    fw.log.panic("Unmapped RSP read: {X:08}", .{address});
}

pub fn write(self: *Self, address: u32, value: u32, mask: u32) void {
    if ((address & 0x000c_0000) == 0) {
        fw.mem.writeMaskedBe(u32, self.mem, address & 0x1ffc, value, mask);
        return;
    }

    if ((address & 0x000c_0000) == 0x0004_0000) {
        self.writeRegister(@truncate(address >> 2), value, mask);
        return;
    }

    if ((address & 0x000f_ffff) == 0x0008_0000) {
        self.core.writePc(@truncate(value), @truncate(mask));
        return;
    }

    fw.log.panic("Unmapped RSP write: {X:08} <= {X:08}", .{ address, value });
}

pub fn readRegister(self: *Self, index: u3) u32 {
    return switch (index) {
        0 => self.sp_addr,
        1 => self.dram_addr,
        2, 3 => @bitCast(self.dma),
        4 => @bitCast(self.status),
        5 => @intFromBool(self.status.dma_full),
        6 => @intFromBool(self.status.dma_busy),
        7 => blk: {
            const value = @intFromBool(self.semaphore);
            self.semaphore = true;
            fw.log.debug("SP_SEMAPHORE: {}", .{self.semaphore});
            break :blk value;
        },
    };
}

pub fn writeRegister(self: *Self, index: u3, value: u32, mask: u32) void {
    switch (index) {
        0 => {
            fw.num.writeMasked(
                u13,
                &self.sp_addr,
                @truncate(value),
                @truncate(mask & ~@as(u32, 7)),
            );

            fw.log.debug("SP_DMA_SPADDR: {X:04}", .{self.sp_addr});
        },
        1 => {
            fw.num.writeMasked(
                u24,
                &self.dram_addr,
                @truncate(value),
                @truncate(mask & ~@as(u32, 7)),
            );

            fw.log.debug("SP_DMA_RAMADDR: {X:08}", .{self.dram_addr});
        },
        2 => {
            fw.num.writeMasked(
                u32,
                @ptrCast(&self.dma),
                @truncate(value),
                @truncate(mask & 0xff8f_fff8),
            );

            fw.log.debug("SP_DMA_RDLEN: {any}", .{self.dma});

            self.transferDma(.read);
        },
        3 => {
            fw.num.writeMasked(
                u32,
                @ptrCast(&self.dma),
                @truncate(value),
                @truncate(mask & 0xff8f_fff8),
            );

            fw.log.debug("SP_DMA_WRLEN: {any}", .{self.dma});

            self.transferDma(.write);
        },
        4 => {
            const masked_value = value & mask;

            register.setFlag(&self.status, "halted", masked_value, 0);
            register.setFlag(&self.status, "sstep", masked_value, 5);
            register.setFlag(&self.status, "intbreak", masked_value, 7);
            register.setFlag(&self.status, "sig0", masked_value, 9);
            register.setFlag(&self.status, "sig1", masked_value, 11);
            register.setFlag(&self.status, "sig2", masked_value, 13);
            register.setFlag(&self.status, "sig3", masked_value, 15);
            register.setFlag(&self.status, "sig4", masked_value, 17);
            register.setFlag(&self.status, "sig5", masked_value, 19);
            register.setFlag(&self.status, "sig6", masked_value, 21);
            register.setFlag(&self.status, "sig7", masked_value, 23);

            if ((masked_value & 4) != 0) {
                self.status.broke = false;
            }

            switch (@as(u2, @truncate(masked_value >> 3))) {
                1 => self.getDevice().mi.clearInterrupt(.sp),
                2 => self.getDevice().mi.raiseInterrupt(.sp),
                else => {},
            }

            fw.log.debug("SP_STATUS: {any}", .{self.status});
        },
        5, 6 => {}, // Read-only
        7 => {
            self.semaphore = false;
            fw.log.debug("SP_SEMAPHORE: {}", .{self.semaphore});
        },
    }
}

// Internal-facing interface

pub fn readInstruction(self: *const Self, address: u12) u32 {
    return fw.mem.readBe(u32, self.mem, @as(u13, 0x1000) | address);
}

pub fn readData(self: *const Self, comptime T: type, address: u12) T {
    if (address <= (bank_size - @sizeOf(T))) {
        @branchHint(.likely);
        return fw.mem.readBe(T, self.mem, address);
    }

    var result: T = fw.mem.readBe(u8, self.mem, address);

    for (1..@sizeOf(T)) |byte| {
        result <<= 8;
        result |= fw.mem.readBe(u8, self.mem, address +% @as(u12, @truncate(byte)));
    }

    return result;
}

pub fn readDataAligned(self: *const Self, comptime T: type, address: u12) T {
    return fw.mem.readBe(T, self.mem, address);
}

pub fn writeData(self: *const Self, comptime T: type, address: u12, value: T) void {
    if (address <= (bank_size - @sizeOf(T))) {
        @branchHint(.likely);
        return fw.mem.writeBe(T, self.mem, address, value);
    }

    var write_value = value;

    for (0..@sizeOf(T)) |byte| {
        write_value = std.math.rotl(T, write_value, 8);
        fw.mem.writeBe(u8, self.mem, address +% @as(u12, @truncate(byte)), @truncate(write_value));
    }
}

pub fn writeDataAligned(self: *const Self, comptime T: type, address: u12, value: T) void {
    fw.mem.writeBe(T, self.mem, address, value);
}

pub fn writeDataAlignedMasked(
    self: *const Self,
    comptime T: type,
    address: u12,
    value: T,
    mask: T,
) void {
    fw.mem.writeMaskedBe(T, self.mem, address, value, mask);
}

pub fn readCp0Register(self: *Self, reg: Core.Cp0Register) u32 {
    if (@intFromEnum(reg) >= @intFromEnum(Core.Cp0Register.DPC_START)) {
        return self.getDevice().rdp.readRegister(@truncate(@intFromEnum(reg)));
    }

    return self.readRegister(@truncate(@intFromEnum(reg)));
}

pub fn writeCp0Register(self: *Self, reg: Core.Cp0Register, value: u32) void {
    if (@intFromEnum(reg) >= @intFromEnum(Core.Cp0Register.DPC_START)) {
        self.getDevice().rdp.writeRegister(
            @truncate(@intFromEnum(reg)),
            value,
            std.math.maxInt(u32),
        );
        return;
    }

    self.writeRegister(
        @truncate(@intFromEnum(reg)),
        value,
        std.math.maxInt(u32),
    );
}

pub fn break_(self: *Self) void {
    self.status.broke = true;
    self.status.halted = true;

    if (self.status.intbreak) {
        self.getDevice().mi.raiseInterrupt(.sp);
    }
}

fn transferDma(self: *Self, comptime direction: DmaDirection) void {
    const rdram = self.getDevice().rdram;
    const sp_bank = self.mem[(self.sp_addr & 0x1000)..][0..bank_size];
    const row_len = @as(u32, self.dma.len) + 8;

    while (true) {
        var sp_index: u12 = @truncate(self.sp_addr);
        var dram_addr: u24 = self.dram_addr;

        for (0..(row_len >> 3)) |_| {
            switch (comptime direction) {
                .read => {
                    const value = if (dram_addr < rdram.len)
                        fw.mem.readBe(u64, rdram, dram_addr)
                    else
                        0;

                    fw.mem.writeBe(u64, sp_bank, sp_index, value);
                },
                .write => if (dram_addr < rdram.len) {
                    const value = fw.mem.readBe(u64, sp_bank, sp_index);
                    fw.mem.writeBe(u64, rdram, dram_addr, value);
                },
            }

            sp_index +%= 8;
            dram_addr +%= 8;
        }

        switch (comptime direction) {
            .read => fw.log.debug("RSP DMA: {} bytes read from {X:08} to MEM:{X:04}", .{
                row_len,
                self.dram_addr,
                self.sp_addr,
            }),
            .write => fw.log.debug("RSP DMA: {} bytes written from MEM:{X:04} to {X:08}", .{
                row_len,
                self.sp_addr,
                self.dram_addr,
            }),
        }

        self.sp_addr = (self.sp_addr & 0x1000) | sp_index;
        self.dram_addr = dram_addr;

        if (self.dma.count == 0) {
            break;
        }

        self.dram_addr +%= self.dma.skip;
        self.dma.count -= 1;
    }

    self.dma.len = 0xff8;
}

fn getDevice(self: *Self) *Device {
    return @alignCast(@fieldParentPtr("rsp", self));
}

const DmaDirection = enum {
    read,
    write,
};

const Dma = packed struct(u32) {
    len: u12 = 0,
    count: u8 = 0,
    skip: u12 = 0,
};

const Status = packed struct(u32) {
    halted: bool = true,
    broke: bool = false,
    dma_busy: bool = false,
    dma_full: bool = false,
    io_busy: bool = false,
    sstep: bool = false,
    intbreak: bool = false,
    sig0: bool = false,
    sig1: bool = false,
    sig2: bool = false,
    sig3: bool = false,
    sig4: bool = false,
    sig5: bool = false,
    sig6: bool = false,
    sig7: bool = false,
    __: u17 = 0,
};
