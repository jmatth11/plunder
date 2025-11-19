const std = @import("std");
const plunder = @import("plunder");

pub fn main() !void {
    const alloc = std.heap.smp_allocator;
    // initialize plunder lib.
    var pl: plunder.Plunder = .init(alloc);
    defer pl.deinit();
    // load mapping info for process ID.
    try pl.load(264537);
    // get region names from memory mapping file.
    const names = try pl.get_region_names(alloc);
    if (names) |name| {
        for (name.items) |entry| {
            std.debug.print("Map name: {s}\n", .{entry});
        }
    }
    // get region data for the heap region.
    const reg_opt = try pl.get_region_data(
        "[heap]",
    );
    if (reg_opt) |*region_ptr| {
        var region = region_ptr.*;
        defer region.deinit();
        // get the non-zero data from the region in a memory list.
        const mem = try region.get_populated_memory(alloc);
        defer mem.deinit();
        for (mem.items) |*memory_ptr| {
            var memory = memory_ptr.*;
            defer memory.deinit();
            std.debug.print("ADDR = {}\n", .{memory.info.start_addr});
            std.debug.print("OFFSET = {}\n", .{memory.starting_offset});
            std.debug.print("BUFFER\n", .{});
            for (memory.buffer.?, 0..) |c, idx| {
                if (std.ascii.isAlphabetic(c)) {
                    std.debug.print("{c} ", .{c});
                } else {
                    std.debug.print("{x} ", .{c});
                }
                if (((idx + 1) % 10) == 0) {
                    std.debug.print("\n", .{});
                }
            }
        }
        std.debug.print("\n", .{});
    }
}
