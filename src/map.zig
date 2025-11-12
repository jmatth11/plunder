const std = @import("std");

/// Undefined name for empty name maps
const UNDEFINED_NAME: []const u8 = "undefined";
/// Process memory mapping file path.
const MAP_FILE: []const u8 = "/proc/%lu/maps";
/// Process memory file path.
const MEM_FILE: []const u8 = "/proc/%lu/mem";

pub const Permissions = enum(u8) {
    read = 1,
    write = 1 << 1,
    execute = 1 << 2,
    shared = 1 << 3,
};

pub const Info = struct {
    alloc: std.mem.Allocator = undefined,
    pathname: ?[]const u8 = null,
    start_addr: usize = 0,
    end_addr: usize = 0,
    perm: u8 = 0,
    offset: u32 = 0,
    dev_major: u8 = 0,
    dev_minor: u8 = 0,
    inode: u32 = 0,

    pub fn init(alloc: std.mem.Allocator) Info {
        var result: Info = .{};
        result.alloc = alloc;
        return result;
    }

    pub fn is_read(self: *Info) bool {
        return (self.perm & Permissions.read) == Permissions.read;
    }
    pub fn is_write(self: *Info) bool {
        return (self.perm & Permissions.write) == Permissions.write;
    }
    pub fn is_execute(self: *Info) bool {
        return (self.perm & Permissions.execute) == Permissions.execute;
    }
    pub fn is_shared(self: *Info) bool {
        return (self.perm & Permissions.shared) == Permissions.shared;
    }

    pub fn deinit(self: *Info) void {
        if (self.pathname) |name| {
            // if not undefined_name it's custom, so we need to free.
            if (!std.mem.eql(u8, UNDEFINED_NAME, name)) {
                self.alloc.free(name);
            }
        }
    }
};

const InfoList = std.array_list.Managed(Info);
const InfoHash = std.hash_map.StringHashMap(InfoList);

const ParseStep = enum(u8) {
    nothing = 0,
    start_addr = 1,
    end_addr = 2,
    perm_read = 3,
    perm_write = 4,
    perm_execute = 5,
    perm_shared = 6,
    offset = 7,
    dev_major = 8,
    dev_minor = 9,
    inode = 10,
    process = 11,
    done = 12,
};
const ParseResult = struct {
    step: ParseStep,
    info: ?Info,
    bytes_read: usize,
};
const ParseInfo = struct {
    alloc: std.mem.Allocator,
    current_step: ParseStep = .nothing,
    current_info: Info = .{},
    working_buffer: [1024]u8 = undefined,
    working_buffer_n: usize = 0,

    pub fn init(alloc: std.mem.Allocator) ParseInfo {
        const result: ParseInfo = .{
            .alloc = alloc,
        };
        return result;
    }

    pub fn parse(self: *ParseInfo, buffer: []const u8, offset: usize) ParseStep {
        var idx: usize = 0;
        while (idx < buffer.len) {
            switch (self.current_step) {
                ParseStep.nothing => self.current_step = .start_addr,
                ParseStep.start_addr => {},
                ParseStep.end_addr => {},
                ParseStep.end_addr => {},
                ParseStep.perm_read => {},
                ParseStep.perm_write => {},
                ParseStep.perm_execute => {},
                ParseStep.perm_shared => {},
                ParseStep.offset => {},
                ParseStep.dev_major => {},
                ParseStep.dev_minor => {},
                ParseStep.inode => {},
                ParseStep.process => {},
                ParseStep.done => {},
            }
        }
    }

    pub fn getInfo(self: *ParseInfo) ?Info {
        if (self.current_step == .done) {
            return self.current_info;
        }
        return null;
    }
};

pub const Manager = struct {
    alloc: std.mem.Allocator,
    collection: InfoHash,
    pid: ?usize,
    map_filename: []const u8,

    pub fn init(alloc: std.mem.Allocator) Manager {
        const result: Manager = .{
            .alloc = alloc,
            .collection = InfoHash.init(alloc),
        };
        return result;
    }

    pub fn load(self: *Manager, pid: usize) !void {
        errdefer self.clear_pid();
        self.map_filename = try std.fmt.allocPrint(self.alloc, MAP_FILE, .{pid});
        self.pid = pid;
        const mem_file = try std.fs.openFileAbsolute(self.map_file, .{});
        defer mem_file.close();
        const buffer: [1024]u8 = undefined;
        var read_n: usize = try mem_file.read(buffer);
        while(read_n > 0) {
            var idx: usize = 0;
            while (idx < read_n) {

            }
            read_n = try mem_file.read(buffer);
        }
    }

    pub fn deinit(self: *Manager) void {
        self.clear_pid();
        self.collection.deinit();
    }

    fn clear_pid(self: *Manager) void {
        if (self.pid != null) {
            self.alloc.free(self.map_filename);
            self.pid = null;
            self.clear_collection();
        }
    }

    fn clear_collection(self: *Manager) void {
        const vit = self.collection.valueIterator();
        while (vit.next()) |value| {
            for (value.items) |entry| {
                entry.deinit();
            }
            value.*.deinit();
        }
        const kit = self.collection.keyIterator();
        while (kit.next()) |key| {
            self.alloc.free(key.*);
        }
        self.collection.clearRetainingCapacity();
    }
};
