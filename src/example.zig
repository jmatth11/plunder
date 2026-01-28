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
}
