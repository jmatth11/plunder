const std = @import("std");

/// Undefined name for empty name maps
const UNDEFINED_NAME: []const u8 = "undefined";
/// Process memory mapping file path.
const MAP_FILE: []const u8 = "/proc/%lu/maps";
/// Process memory file path.
const MEM_FILE: []const u8 = "/proc/%lu/mem";

pub const Errors = error {
    malformed_permissions,
};

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

    pub fn set_read(self: *Info) void {
        self.perm = self.perm | Permissions.read;
    }
    pub fn set_write(self: *Info) void {
        self.perm = self.perm | Permissions.write;
    }
    pub fn set_execute(self: *Info) void {
        self.perm = self.perm | Permissions.execute;
    }
    pub fn set_shared(self: *Info) void {
        self.perm = self.perm | Permissions.shared;
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
    step: ParseStep = .nothing,
    info: ?Info = null,
    bytes_read: usize = 0,
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

    pub fn parse(self: *ParseInfo, buffer: []const u8, offset: usize) ParseResult {
        var idx: usize = offset;
        while (idx < buffer.len) {
            switch (self.current_step) {
                ParseStep.nothing => self.current_step = .start_addr,
                ParseStep.start_addr => {
                    const res = self.parse_addr(buffer, idx, .end_addr);
                    if (res.step == .end_addr) {
                        self.current_info.start_addr = try std.fmt.parseInt(
                            u8,
                            self.working_buffer[0..self.working_buffer_n],
                            16
                        );
                    }
                    idx += res.bytes_read;
                    self.current_step = res.step;
                },
                ParseStep.end_addr => {
                    const res = self.parse_addr(buffer, idx, .perm_read);
                    if (res.step == .perm_read) {
                        self.current_info.end_addr = try std.fmt.parseInt(
                            u8,
                            self.working_buffer[0..self.working_buffer_n],
                            16
                        );
                    }
                    idx += res.bytes_read;
                    self.current_step = res.step;
                },
                ParseStep.perm_read => {
                    const res = try ParseInfo.parse_permission(buffer, idx, 'r');
                    if (res) {
                        self.current_info.set_read();
                    }
                    idx += 1;
                    self.current_step = .perm_write;
                },
                ParseStep.perm_write => {
                    const res = try ParseInfo.parse_permission(buffer, idx, 'w');
                    if (res) {
                        self.current_info.set_write();
                    }
                    idx += 1;
                    self.current_step = .perm_execute;
                },
                ParseStep.perm_execute => {
                    const res = try ParseInfo.parse_permission(buffer, idx, 'x');
                    if (res) {
                        self.current_info.set_execute();
                    }
                    idx += 1;
                    self.current_step = .perm_shared;
            },
                ParseStep.perm_shared => {
                    const res = try ParseInfo.parse_permission(buffer, idx, 's');
                    if (res) {
                        self.current_info.set_shared();
                    }
                    // skip 2 to skip next whitespace.
                    idx += 2;
                    self.current_step = .offset;
            },
                ParseStep.offset => {
                    const res = self.parse_addr(buffer, idx, .dev_major);
                    if (res.step == .dev_major) {
                        self.current_info.offset = try std.fmt.parseInt(
                            u8,
                            self.working_buffer[0..self.working_buffer_n],
                            16
                        );
                    }
                    idx += res.bytes_read;
                    self.current_step = res.step;
                },
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

    fn parse_addr(self: *ParseInfo, buffer: []const u8, offset: usize, next_step: ParseStep) ParseResult {
        var result: ParseResult = .{.step = self.current_step};
        var idx: usize = offset;
        self.working_buffer_n = 0;
        while (idx < buffer.len) : (idx += 1) {
            if (std.ascii.isAlphanumeric(buffer[idx])) {
                self.working_buffer[self.working_buffer_n] = buffer[idx];
                self.working_buffer_n += 1;
            } else {
                result.step = next_step;
                break;
            }
        }
        result.bytes_read = idx;
        // add one extra if we completed the parse to move past the hyphen char.
        if (result.step == next_step) {
            result.bytes_read += 1;
        }
        return result;
    }

    fn parse_permission(buffer: []const u8, offset: usize, compare_char: u8) Errors!bool {
        if (buffer[offset] == compare_char) {
            return true;
        } else if (buffer[offset] != '-' and buffer[offset] != 'p') {
             return Errors.malformed_permissions;
        }
        return false;
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
