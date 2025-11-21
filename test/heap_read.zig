const std = @import("std");
const plunder = @import("plunder");

const Errors = error {
    missing_pid,
};

const TEST_STR: []const u8 = "test string";

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
    // initialize plunder lib.
    var pl: plunder.Plunder = .init(alloc);
    defer pl.deinit();
    // load mapping info for process ID.
    try pl.load(pid);

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
        var contains_test_str: bool = false;
        for (mem.items) |*memory_ptr| {
            var memory = memory_ptr.*;
            defer memory.deinit();
            if (std.mem.eql(u8, TEST_STR, memory.buffer.?)) {
                contains_test_str = true;
            }
        }
        try std.testing.expect(contains_test_str);
    }
}
