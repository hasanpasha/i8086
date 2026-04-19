regions: []const MemoryRegion,

const Self = @This();

fn findRegion(self: *const Self, addr: u20) ?*const MemoryRegion {
    var i: usize = 0;
    var j: usize = self.regions.len;

    var best: ?*const MemoryRegion = null;

    while (i < j) {
        const mid = (i + j) / 2;
        const r = &self.regions[mid];

        if (r.start <= addr) {
            best = r;
            i = mid + 1;
        } else {
            j = mid;
        }
    }

    return best;
}

pub fn read(self: Self, addr: u20) u8 {
    return if (self.findRegion(addr)) |region| region.read(addr) else 0xAA;
}

pub fn write(self: Self, addr: u20, value: u8) void {
    if (self.findRegion(addr)) |region|
        region.write(addr, value);
}

const MemoryRegion = @import("MemoryRegion.zig");

// 00000 - 7FFFF  RAM (512 KB)
// 80000 - 9FFFF  VGA memory
// A0000 - EFFFF  MMIO / reserved
// F0000 - FFFFF  BIOS ROM
