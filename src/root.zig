/// namespace for memory mapping info for a given process.
pub const map = @import("map.zig");
/// namespace for reading memory from the given mapping info and process.
pub const mem = @import("mem.zig");
/// Plunder structure to grab memory from a running process.
/// Most interactions will be done through this structure.
pub const Plunder = mem.Plunder;
/// List of strings type.
pub const StringList = map.StringList;
/// List of Memory structure type.
pub const MemoryList = mem.MemoryList;
