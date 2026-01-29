# Plunder

Contents:
- [Example](#example)
- [Testing](#testing)
- [TUI Demo](#tui-demo)
    - [Reading Memory](#reading-memory)
    - [View Info](#view-info)

Plunder allows you read/write memory from a running process on linux and grab basic network information.

This repo is a library and a TUI.

Currently the TUI only implements a subset of what the library can do.

The TUI is build with `zig build -Doptimize=ReleaseSafe`. Run it with `sudo ./zig-out/bin/plunder`.

Current functionality:
- Read Memory from a given process.
    - Get the list of region names
    - Read the raw data from the Region.
    - Read only populated data from the Region.
- Write to memory to a given process.
- Read basic network information from a given process.
    - Read what ports and protocols a process is using.


> [!WARNING]
> This library is still in the early stages and the API may change.

## Example

```zig
const std = @import("std");
const plunder = @import("plunder");

pub fn main() !void {
    const alloc = std.heap.smp_allocator;

    // initialize plunder lib.
    var pl: plunder.Plunder = .init(alloc);
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

## Testing

The folder `test` contains a simple example of testing against a C program
that allocates memory on the heap.

The `heap_read.zig` file accepts the process ID to read from and searches for
the test text that is allocated in the `dummy.c` file.

You can run this test with the `run_test.sh` script at the top of the repo.


## TUI Demo

### Reading Memory

https://github.com/user-attachments/assets/b5638b15-ee20-439e-beef-37de7d8a390b

### View Info

https://github.com/user-attachments/assets/68256d09-6742-4adc-865b-9685bd48b510
