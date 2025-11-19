# Plunder

A simple library to read memory from a running process.

!! warning !!
This library is still in the early stages and the API may change.

- [ ] TODO finish readme

## Example

```zig
const std = @import("std");
const plunder = @import("plunder");

pub fn main() !void {
    const alloc = std.heap.smp_allocator;

    // initialize plunder lib.
    var pl: plunder.mem.Plunder = .init(alloc);
    defer pl.deinit();

    // load mapping info for process ID.
    try pl.load(<pid>);

    // get region names from memory mapping file.
    const names = try pl.get_region_names(alloc);
    if (names) |name| {
        for (name.items) |entry| {
            // operate on names
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
            for (memory.buffer.?) |c| {
                // operate on buffer data.
            }
        }
    }
}
```
