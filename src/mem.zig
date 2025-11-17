const std = @import("std");
const map = @import("map.zig");

/// Process memory file path.
const MEM_FILE: []const u8 = "/proc/%lu/mem";

pub const Memory = struct {
    alloc: std.mem.Allocator = undefined,
    info: map.Info = undefined,
    starting_offset: usize = 0,
    buffer: ?[]const u8 = null,

    pub fn init(alloc: std.mem.Allocator, info: map.Info) !Memory {
        const result: Memory = .{
            .alloc = alloc,
            .info = try info.dupe(alloc),
        };
        return result;
    }
    pub fn init_with_buffer(alloc: std.mem.Allocator, buffer: []const u8, info: map.Info) !Memory {
        var result: Memory = .{
            .gpa = .init(std.heap.smp_allocator),
        };
        result.alloc = result.gpa.allocator();
        result.info = try info.dupe(alloc);
        result.buffer = try result.alloc.dupe(u8, buffer);
        return result;
    }

    pub fn deinit(self: *Memory) void {
        self.info.deinit();
        if (self.buffer) |buf| {
            self.alloc.free(buf);
            self.buffer = null;
        }
    }
};

pub const MemoryList = std.array_list.Managed(Memory);

pub const Region = struct {
    gpa: std.heap.ArenaAllocator,
    alloc: std.mem.Allocator = undefined,
    memory: MemoryList = undefined,

    pub fn init() Region {
        var result: Region = .{
            .gpa = .init(std.heap.smp_allocator),
        };
        result.alloc = result.gpa.allocator();
        result.memory = .init(result.alloc);
        return result;
    }

    pub fn add(self: *Region, entry: Memory) !void {
        try self.memory.append(entry);
    }

    pub fn deinit(self: *Region) void {
        self.gpa.deinit();
    }
};

pub const Plunder = struct {
    alloc: std.mem.Allocator,
    pid: ?usize = null,
    mem_filename: []const u8 = undefined,
    map_manager: map.Manager = undefined,

    pub fn init(alloc: std.mem.Allocator) Plunder {
        const result: Plunder = .{
            .alloc = alloc,
            .map_manager = .init(alloc),
        };
        return result;
    }

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

    pub fn get_region_names(self: *Plunder, alloc: std.mem.Allocator) !?map.StringList {
        if (self.pid == null) {
            return null;
        }
        return self.map_manager.get_region_names(alloc);
    }

    pub fn get_region_data(self: *Plunder, region: []const u8) !?Region {
        // TODO create region of memory
    }

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
