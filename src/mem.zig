const std = @import("std");
const map = @import("map.zig");

/// Process memory file path.
const MEM_FILE: []const u8 = "/proc/{}/mem";

/// Memory structure to hold the buffer of mapped memory.
pub const Memory = struct {
    alloc: std.mem.Allocator = undefined,
    /// Mapped info data.
    info: map.Info = undefined,
    /// Starting offset is set if the buffer starts later than info.start_addr.
    starting_offset: usize = 0,
    buffer: ?[]const u8 = null,

    /// Initialize with a given mapped info structure.
    pub fn init(alloc: std.mem.Allocator, info: *const map.Info) !Memory {
        const result: Memory = .{
            .alloc = alloc,
            .info = try info.dupe(alloc),
        };
        return result;
    }
    /// Initialize with a given buffer and mapped info structure.
    pub fn init_with_buffer(alloc: std.mem.Allocator, buffer: []const u8, info: map.Info) !Memory {
        var result: Memory = .{
            .alloc = alloc,
        };
        result.info = try info.dupe(alloc);
        result.buffer = try result.alloc.dupe(u8, buffer);
        return result;
    }

    /// Deinitialize.
    pub fn deinit(self: *Memory) void {
        self.info.deinit();
        if (self.buffer) |buf| {
            self.alloc.free(buf);
            self.buffer = null;
        }
    }
};

/// Array list of Memory structures.
pub const MemoryList = std.array_list.Managed(Memory);

/// Region represents a collection of mapped memory info and data for a region.
pub const Region = struct {
    gpa: *std.heap.ArenaAllocator,
    alloc: std.mem.Allocator,
    memory: MemoryList = undefined,

    /// Initialize a Region with a given allocator.
    pub fn init(alloc: std.mem.Allocator) !Region {
        var result: Region = .{
            .gpa = try alloc.create(std.heap.ArenaAllocator),
            .alloc = alloc,
        };
        result.gpa.* = .init(alloc);
        result.memory = .init(result.gpa.allocator());
        return result;
    }

    /// Add a given memory structure to the list.
    pub fn add(self: *Region, entry: Memory) !void {
        try self.memory.append(entry);
    }

    /// Generate and add a memory from the given memory file and mapping info.
    pub fn generate_memory(self: *Region, file: std.fs.File, info: *const map.Info) !void {
        const len: usize = info.end_addr - info.start_addr;
        const alloc = self.gpa.allocator();
        var result: Memory = try .init(alloc, info);
        const buffer: []u8 = try alloc.alloc(u8, len);
        try file.seekTo(info.start_addr);
        _ = try file.read(buffer);
        result.buffer = buffer;
        try self.add(result);
    }

    /// Get the list of populated memory slices from the region.
    /// This function filters out all the zero byte data.
    /// The user is responsible for freeing the returned value.
    pub fn get_populated_memory(self: *Region, alloc: std.mem.Allocator) !MemoryList {
        var result: MemoryList = .init(alloc);
        for (self.memory.items) |memory| {
            var start_idx: usize = 0;
            var cur_idx: usize = 0;
            var capturing: bool = false;
            if (memory.buffer) |buf| {
                while (cur_idx < buf.len) : (cur_idx += 1) {
                    if (!capturing and (buf[cur_idx] > 0)) {
                        capturing = true;
                        start_idx = cur_idx;
                    }
                    if (capturing and (buf[cur_idx] == 0)) {
                        var new_mem: Memory = try .init_with_buffer(
                            alloc,
                            buf[start_idx..cur_idx],
                            memory.info,
                        );
                        new_mem.starting_offset = start_idx;
                        try result.append(new_mem);
                        capturing = false;
                    }
                }
            }
        }
        return result;
    }

    /// Deinitialize.
    pub fn deinit(self: *Region) void {
        self.gpa.deinit();
        std.heap.smp_allocator.destroy(self.gpa);
    }
};

/// Plunder Structure for accessing memory of a running process.
///
/// This structure can load and access a running processes' memory.
/// Calling the load function will clear the previous loaded memory.
pub const Plunder = struct {
    alloc: std.mem.Allocator,
    pid: ?usize = null,
    mem_filename: []const u8 = undefined,
    map_manager: map.Manager = undefined,

    /// Initialize Plunder structure.
    pub fn init(alloc: std.mem.Allocator) Plunder {
        const result: Plunder = .{
            .alloc = alloc,
            .map_manager = .init(alloc),
        };
        return result;
    }

    /// Load in the mapped memory info for a given process ID.
    pub fn load(self: *Plunder, pid: usize) !void {
        self.clear_pid();
        errdefer self.clear_pid();
        self.mem_filename = try std.fmt.allocPrint(
            self.alloc,
            MEM_FILE,
            .{pid},
        );
        self.pid = pid;
        try self.map_manager.load(pid);
    }

    /// Get the list of region names.
    /// If a process has not been loaded, null is returned.
    pub fn get_region_names(self: *Plunder, alloc: std.mem.Allocator) !?map.StringList {
        if (self.pid == null) {
            return null;
        }
        return self.map_manager.get_region_names(alloc);
    }

    /// Get the data for a given region.
    /// If the region does not exist null is returned.
    pub fn get_region_data(self: *Plunder, region: []const u8) !?Region {
        if (try self.map_manager.get_region(region)) |info_col| {
            var result: Region = try .init(self.alloc);
            const mem_file = try std.fs.openFileAbsolute(
                self.mem_filename,
                .{ .mode = .read_only },
            );
            defer mem_file.close();
            for (info_col.items) |info| {
                try result.generate_memory(mem_file, &info);
            }
            return result;
        }
        return null;
    }

    /// Deinitialize.
    pub fn deinit(self: *Plunder) void {
        self.clear_pid();
        self.map_manager.deinit();
    }

    fn clear_pid(self: *Plunder) void {
        if (self.pid != null) {
            self.alloc.free(self.mem_filename);
            self.pid = null;
        }
    }
};
