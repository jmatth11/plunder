const std = @import("std");
const plunder = @import("plunder");

const Errors = error {
    missing_pid,
};

// This program takes a process ID as a command line argument and reads out the
// heap memory. It only prints out non-zero values from the heap.

pub fn main() !void {
    var args = std.process.args();
    defer args.deinit();

    // skip main file
    _ = args.next();
    const pid_arg = args.next();
    if (pid_arg == null) {
        return Errors.missing_pid;
    }

    var pid: usize = undefined;
    if (pid_arg) |p| {
        pid = try std.fmt.parseInt(usize, p, 10);
    }

    const alloc = std.heap.smp_allocator;
    const network_info = try plunder.network.get_tcp_info(alloc, pid);
    defer alloc.free(network_info);

    var fs = std.fs.File.stdout();
    var buf: [1024]u8 = undefined;
    var writer = fs.writer(&buf);

    for (network_info, 0..) |info, idx| {
        if (idx == 0) {
            try info.format(&writer.interface, true);
        } else {
            try info.format(&writer.interface, false);
        }
    }
    try writer.interface.flush();
    //// initialize plunder lib.
    //var pl: plunder.Plunder = .init(alloc);
    //defer pl.deinit();
    //// load mapping info for process ID.
    //try pl.load(pid);
    //// get region names from memory mapping file.
    //const names = try pl.get_region_names(alloc);
    //if (names) |name| {
    //    for (name.items) |entry| {
    //        std.debug.print("Map name: {s}\n", .{entry});
    //    }
    //}
    //// get region data for the heap region.
    //const reg_opt = try pl.get_region_data(
    //    "[heap]",
    //);
    //var buffer: [1024]u8 = undefined;
    //if (reg_opt) |*region_ptr| {
    //    var region = region_ptr.*;
    //    defer region.deinit();
    //    //// get the non-zero data from the region in a memory list.
    //    const mem = try region.get_populated_memory(alloc);
    //    defer mem.deinit();
    //    for (mem.items) |memory| {
    //        var wr = std.fs.File.stdout().writer(&buffer);
    //        try memory.hex_dump(&wr.interface);
    //    }
    //}
}
