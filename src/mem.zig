const std = @import("std");
const map = @import("map.zig");
const common = @import("common.zig");

/// Process memory file path.
const MEM_FILE: []const u8 = "/proc/{}/mem";

/// Errors related to Memory
pub const Errors = error{
    memory_buffer_not_set,
    out_of_bounds,
    not_writable,
};

pub const MutableMemory = struct {
    alloc: std.mem.Allocator = undefined,
    /// Mapped info data.
    info: map.Info = undefined,
    /// Starting offset is set if the buffer starts later than info.start_addr.
    starting_offset: usize = 0,
    /// Memory buffer
    buffer: ?[]u8 = null,

    /// Initialize with a given mapped info structure.
    pub fn init(alloc: std.mem.Allocator, info: *const map.Info) !MutableMemory {
        const result: MutableMemory = .{
            .alloc = alloc,
            .info = try info.dupe(alloc),
        };
        return result;
    }
    /// Initialize with a given buffer and mapped info structure.
    pub fn init_with_buffer(alloc: std.mem.Allocator, buffer: []const u8, info: *const map.Info) !MutableMemory {
        var result: MutableMemory = .{
            .alloc = alloc,
        };
        result.info = try info.dupe(alloc);
        result.buffer = try result.alloc.dupe(u8, buffer);
        return result;
    }

    /// Deinitialize.
    pub fn deinit(self: *MutableMemory) void {
        self.info.deinit();
        if (self.buffer) |buf| {
            self.alloc.free(buf);
            self.buffer = null;
        }
    }
};

/// Memory structure to hold the buffer of mapped memory.
pub const Memory = struct {
    alloc: std.mem.Allocator = undefined,
    /// Mapped info data.
    info: map.Info = undefined,
    /// Starting offset is set if the buffer starts later than info.start_addr.
    starting_offset: usize = 0,
    /// Memory buffer
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
    pub fn init_with_buffer(alloc: std.mem.Allocator, buffer: []const u8, info: *const map.Info) !Memory {
        var result: Memory = .{
            .alloc = alloc,
        };
        result.info = try info.dupe(alloc);
        result.buffer = try result.alloc.dupe(u8, buffer);
        return result;
    }

    /// Write a given buffer to the memory offset.
    pub fn write(self: *Memory, offset: usize, buf: []const u8) !usize {
        if (self.buffer == null) {
            return Errors.memory_buffer_not_set;
        }
        if (!self.info.is_write()) {
            return Errors.not_writable;
        }
        const buffer = self.buffer.?;
        if ((offset + buf.len) > buffer.len) {
            return Errors.out_of_bounds;
        }
        var starting_idx: usize = offset;
        var buf_idx: usize = 0;
        const end: usize = offset + buf.len;

        var new_buffer: []u8 = try self.alloc.dupe(u8, buffer);
        errdefer self.alloc.free(new_buffer);

        while (starting_idx < end) {
            new_buffer[starting_idx] = buf[buf_idx];
            starting_idx += 1;
            buf_idx += 1;
        }

        const filename = try std.fmt.allocPrint(self.alloc, MEM_FILE, .{self.info.pid});
        defer self.alloc.free(filename);

        const fs = try std.fs.openFileAbsolute(filename, .{
            .mode = .write_only,
        });
        defer fs.close();

        try fs.seekTo(self.info.start_addr + self.starting_offset + offset);
        const result = try fs.write(new_buffer[offset..(offset + buf.len)]);
        self.alloc.free(buffer);
        self.buffer = new_buffer;
        return result;
    }

    /// Write out the memory info in a hex dump style.
    pub fn hex_dump(self: *const Memory, writer: *std.io.Writer) !void {
        if (self.buffer == null) {
            return Errors.memory_buffer_not_set;
        }
        var offset: usize = 0;
        const end: usize = offset + self.buffer.?.len;
        const base_addr: usize = self.info.start_addr + self.starting_offset;
        while (offset < end) {
            try writer.*.print("{X:0>12}: ", .{base_addr + offset});
            var byte_idx: usize = 0;
            while (byte_idx < 16) : (byte_idx += 1) {
                const idx: usize = offset + byte_idx;
                if (idx < self.buffer.?.len) {
                    try writer.*.print("{X:0>2} ", .{self.buffer.?[idx]});
                } else {
                    _ = try writer.*.write("   ");
                }
            }
            byte_idx = 0;
            _ = try writer.*.write("|");
            while (byte_idx < 16) : (byte_idx += 1) {
                const idx: usize = offset + byte_idx;
                if (idx < self.buffer.?.len) {
                    const local_char: u8 = self.buffer.?[idx];
                    if (local_char >= 33 and local_char <= 126) {
                        try writer.*.print("{c}", .{self.buffer.?[idx]});
                    } else {
                        _ = try writer.*.write(".");
                    }
                } else {
                    _ = try writer.*.write(".");
                }
            }
            _ = try writer.*.write("|\n");
            offset += 16;
        }
        try writer.*.flush();
    }

    /// Generate a hex dump line from the given offset into the memory.
    /// The offset is represented as 16 bytes at a time.
    pub fn hex_dump_line(self: *const Memory, alloc: std.mem.Allocator, line_offset: usize) !?[]const u8 {
        if (self.buffer == null) {
            return Errors.memory_buffer_not_set;
        }
        const offset: usize = line_offset * 16;
        if (offset >= self.buffer.?.len) {
            return Errors.out_of_bounds;
        }
        const base_addr: usize = self.info.start_addr + self.starting_offset;
        var buffer: [1024]u8 = @splat(0);
        var writer: std.io.Writer = .fixed(&buffer);
        try writer.print("{X:0>12}: ", .{base_addr + offset});
        var byte_idx: usize = 0;
        while (byte_idx < 16) : (byte_idx += 1) {
            const idx: usize = offset + byte_idx;
            if (idx < self.buffer.?.len) {
                try writer.print("{X:0>2} ", .{self.buffer.?[idx]});
            } else {
                _ = try writer.write("   ");
            }
        }
        byte_idx = 0;
        _ = try writer.write("|");
        while (byte_idx < 16) : (byte_idx += 1) {
            const idx: usize = offset + byte_idx;
            if (idx < self.buffer.?.len) {
                const local_char: u8 = self.buffer.?[idx];
                if (local_char >= 33 and local_char <= 126) {
                    try writer.print("{c}", .{self.buffer.?[idx]});
                } else {
                    _ = try writer.write(".");
                }
            } else {
                _ = try writer.write(".");
            }
        }
        _ = try writer.write("|\n");
        return try alloc.dupe(u8, buffer[0..writer.end]);
    }

    /// Create a duplicate of the memory structure with a given allocator.
    pub fn dupe(self: *const Memory, alloc: std.mem.Allocator) !Memory {
        if (self.buffer) |buffer| {
            return try .init_with_buffer(alloc, buffer, &self.info);
        } else {
            return try .init(alloc, &self.info);
        }
    }

    /// Create a mutable copy of the memory.
    pub fn to_mutable(self: *const Memory, alloc: std.mem.Allocator) !MutableMemory {
        if (self.buffer) |buffer| {
            return try .init_with_buffer(alloc, buffer, &self.info);
        } else {
            return try .init(alloc, &self.info);
        }
    }

    /// Create a mutable copy of the memory.
    pub fn to_mutable_range(self: *const Memory, alloc: std.mem.Allocator, start: usize, end: usize) !MutableMemory {
        if (self.buffer) |buffer| {
            if (start < buffer.len and end < buffer.len and start < end) {
                var result: MutableMemory = try .init_with_buffer(alloc, buffer[start..end], &self.info);
                result.starting_offset = start;
                return result;
            } else {
                return Errors.out_of_bounds;
            }
        } else {
            return try .init(alloc, &self.info);
        }
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
                            &memory.info,
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
    pub fn get_region_names(self: *Plunder, alloc: std.mem.Allocator) !?common.StringList {
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
