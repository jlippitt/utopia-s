const fw = @import("framework");
const Ppu = @import("../Ppu.zig");

pub fn copyScrollX(ppu: *Ppu) void {
    ppu.address.coarse_x = ppu.tmp_address.coarse_x;
    ppu.address.name_table_x = ppu.tmp_address.name_table_x;
    fw.log.debug("VRAM Address (Copy Scroll X): {X:04}", .{ppu.address.get()});
}

pub fn copyScrollY(ppu: *Ppu) void {
    ppu.address.coarse_y = ppu.tmp_address.coarse_y;
    ppu.address.name_table_y = ppu.tmp_address.name_table_y;
    ppu.address.fine_y = ppu.tmp_address.fine_y;
    fw.log.debug("VRAM Address (Copy Scroll Y): {X:04}", .{ppu.address.get()});
}

pub fn incrementScrollX(ppu: *Ppu) void {
    ppu.address.coarse_x +%= 1;

    if (ppu.address.coarse_x == 0) {
        @branchHint(.unlikely);
        ppu.address.name_table_x ^= 1;
    }
}

pub fn incrementScrollY(ppu: *Ppu) void {
    ppu.address.fine_y +%= 1;

    if (ppu.address.fine_y == 0) {
        @branchHint(.unlikely);
        ppu.address.coarse_y +%= 1;

        if (ppu.address.coarse_y == 30) {
            @branchHint(.unlikely);
            ppu.address.coarse_y = 0;
            ppu.address.name_table_y ^= 1;
        }
    }

    fw.log.debug("VRAM Address (Increment Scroll Y): {X:04}", .{ppu.address.get()});
}
