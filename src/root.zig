/// namespace for memory mapping info for a given process.
pub const map = @import("map.zig");
/// namespace for reading memory from the given mapping info and process.
pub const mem = @import("mem.zig");
/// namespace for network info.
pub const network = @import("network.zig");
/// helper functions to interact with processes.
pub const proc = @import("proc.zig");
/// Common structures and functions.
pub const common = @import("common.zig");
/// Plunder structure to grab memory from a running process.
/// Most interactions will be done through this structure.
pub const Plunder = mem.Plunder;
/// List of Memory structure type.
pub const MemoryList = mem.MemoryList;
