const std = @import("std");
const common = @import("common.zig");

/// Undefined name for empty name maps
pub const UNDEFINED_NAME: []const u8 = "undefined";
/// Process memory mapping file path.
const MAP_FILE: []const u8 = "/proc/{}/maps";

/// Errors related to Map manager.
pub const Errors = error{
    /// Permissions are malformed
    malformed_permissions,
    /// Missing process ID.
    missing_pid,
};

/// Permission values for memory map.
pub const Permissions = enum(u8) {
    read = 1,
    write = 1 << 1,
    execute = 1 << 2,
    shared = 1 << 3,

    /// Set (OR'ed together) the permission to the given value.
    pub fn set_perm(self: Permissions, original: u8) u8 {
        const val: u8 = @intFromEnum(self);
        return original | val;
    }

    /// Check if the given value has the permission set.
    pub fn check_perm(self: Permissions, original: u8) bool {
        const val: u8 = @intFromEnum(self);
        return (original & val) == val;
    }
};

// ref: https://man7.org/linux/man-pages/man5/proc_pid_maps.5.html

/// Memory Info structure
/// This structure holds all the info for a memory mapped entry.
pub const Info = struct {
    alloc: std.mem.Allocator = undefined,
    /// The process ID.
    pid: usize = 0,
    /// The pathname the memory map belongs to.
    pathname: ?[]const u8 = null,
    /// The starting address in the associated memory file.
    start_addr: usize = 0,
    /// The ending address in the associated memory file.
    end_addr: usize = 0,
    /// The permissions the memory mapped region has.
    perm: u8 = 0,
    /// The offset.
    offset: usize = 0,
    /// The device major version.
    dev_major: u16 = 0,
    /// The device minor version.
    dev_minor: u16 = 0,
    /// The associated inode
    inode: usize = 0,

    /// Initialize an Info structure with a given allocator
    pub fn init(alloc: std.mem.Allocator) Info {
        var result: Info = .{};
        result.alloc = alloc;
        return result;
    }

    /// Create a deep copy of this Info structure.
    pub fn dupe(self: *const Info, alloc: std.mem.Allocator) !Info {
        var local_pathname: ?[]const u8 = null;
        if (self.pathname) |name| {
            local_pathname = try alloc.dupe(u8, name);
        }
        return .{
            .alloc = alloc,
            .pid = self.pid,
            .pathname = local_pathname,
            .start_addr = self.start_addr,
            .end_addr = self.end_addr,
            .perm = self.perm,
            .offset = self.offset,
            .dev_major = self.dev_major,
            .dev_minor = self.dev_minor,
            .inode = self.inode,
        };
    }

    /// Check if the read permission is set.
    pub fn is_read(self: *const Info) bool {
        return Permissions.read.check_perm(self.perm);
    }
    /// Check if the write permission is set.
    pub fn is_write(self: *const Info) bool {
        return Permissions.write.check_perm(self.perm);
    }
    /// Check if the execute permission is set.
    pub fn is_execute(self: *const Info) bool {
        return Permissions.execute.check_perm(self.perm);
    }
    /// Check if the shared permission is set.
    pub fn is_shared(self: *const Info) bool {
        return Permissions.shared.check_perm(self.perm);
    }

    // TODO should add flag to allow setting and unsetting permissions.
    /// Set the read permission.
    pub fn set_read(self: *Info) void {
        self.perm = Permissions.read.set_perm(self.perm);
    }
    /// Set the write permission.
    pub fn set_write(self: *Info) void {
        self.perm = Permissions.write.set_perm(self.perm);
    }
    /// Set the execute permission.
    pub fn set_execute(self: *Info) void {
        self.perm = Permissions.execute.set_perm(self.perm);
    }
    /// Set the shared permission.
    pub fn set_shared(self: *Info) void {
        self.perm = Permissions.shared.set_perm(self.perm);
    }

    /// Deinitialize internals.
    pub fn deinit(self: *Info) void {
        if (self.pathname) |name| {
            // if not undefined_name it's custom, so we need to free.
            if (!std.mem.eql(u8, UNDEFINED_NAME, name)) {
                self.alloc.free(name);
            }
        }
    }
};

/// Array list of info structures.
const InfoList = std.array_list.Managed(Info);
/// A string hash map of InfoLists
const InfoHash = std.hash_map.StringHashMap(InfoList);

/// Parse a line from the memory mapping file of a process.
fn parse_map_line(alloc: std.mem.Allocator, line: []const u8) !Info {
    var result: Info = .init(alloc);
    var parser: std.fmt.Parser = .{ .bytes = line, .i = 0 };

    const start_addr = parser.until('-');
    result.start_addr = try std.fmt.parseInt(
        usize,
        start_addr,
        16,
    );
    // increment past '-'
    parser.i += 1;

    const end_addr = parser.until(' ');
    result.end_addr = try std.fmt.parseInt(
        usize,
        end_addr,
        16,
    );
    parser.i += 1;

    var perm_bit = parser.char();
    if (perm_bit) |bit| {
        if (bit == 'r') {
            result.set_read();
        }
    }
    perm_bit = parser.char();
    if (perm_bit) |bit| {
        if (bit == 'w') {
            result.set_write();
        }
    }
    perm_bit = parser.char();
    if (perm_bit) |bit| {
        if (bit == 'x') {
            result.set_execute();
        }
    }
    perm_bit = parser.char();
    if (perm_bit) |bit| {
        if (bit == 's') {
            result.set_shared();
        }
    }
    // skip next space.
    parser.i += 1;

    const offset = parser.until(' ');
    result.offset = try std.fmt.parseInt(
        usize,
        offset,
        16,
    );
    parser.i += 1;

    const dev_major = parser.until(':');
    result.dev_major = try std.fmt.parseInt(
        u16,
        dev_major,
        16,
    );
    parser.i += 1;

    const dev_minor = parser.until(' ');
    result.dev_minor = try std.fmt.parseInt(
        u16,
        dev_minor,
        16,
    );
    parser.i += 1;

    const inode = parser.until(' ');
    result.inode = try std.fmt.parseInt(usize, inode, 10);
    parser.i += 1;
    var next_char = parser.peek(1);
    // some lines end at this point so we check.
    if (parser.i >= line.len or next_char == null or (next_char != null and next_char.? == '\n')) {
        return result;
    }
    // skip all whitespace
    while (next_char != null and next_char.? == ' ') {
        parser.i += 1;
        next_char = parser.peek(1);
    }
    parser.i += 1;

    const process = parser.until('\n');
    if (process.len > 0) {
        result.pathname = try alloc.dupe(u8, process);
    }

    return result;
}

/// Manager structure to read memory mapped info for a given process.
pub const Manager = struct {
    alloc: std.mem.Allocator,
    collection: InfoHash,
    pid: ?usize = null,
    map_filename: []const u8 = undefined,

    /// Initialize manager with allocator.
    pub fn init(alloc: std.mem.Allocator) Manager {
        const result: Manager = .{
            .alloc = alloc,
            .collection = InfoHash.init(alloc),
        };
        return result;
    }

    /// Load the memory mapped info for the given process ID.
    pub fn load(self: *Manager, pid: usize) !void {
        if (self.pid != null) {
            self.clear_pid();
            self.clear_collection();
        }
        errdefer self.clear_pid();
        self.map_filename = try std.fmt.allocPrint(self.alloc, MAP_FILE, .{pid});
        self.pid = pid;
        const mem_file = try std.fs.openFileAbsolute(self.map_filename, .{});
        defer mem_file.close();
        var read_buf: [2048]u8 = undefined;

        var file_reader = mem_file.reader(&read_buf);
        while (try file_reader.interface.takeDelimiter('\n')) |line| {
            var info = try parse_map_line(self.alloc, line);
            try self.add_entry(&info);
        }
    }

    /// Get the list of region names of mapped memory.
    /// User is responsible for managing the returned resources.
    pub fn get_region_names(self: *Manager, alloc: std.mem.Allocator) !?common.StringListManager {
        var kit = self.collection.keyIterator();
        if (kit.len == 0) {
            return null;
        }
        var result: common.StringListManager = .init(alloc);
        while (kit.next()) |key| {
            try result.add(key.*);
        }
        return result;
    }

    /// Get the all the region info for the given region name.
    pub fn get_region(self: *Manager, key: []const u8) !?InfoList {
        return self.collection.get(key);
    }

    /// Deinitialize internals.
    pub fn deinit(self: *Manager) void {
        self.clear_pid();
        self.clear_collection();
        self.collection.deinit();
    }

    /// Add info entry.
    fn add_entry(self: *Manager, info: *Info) !void {
        if (self.pid) |pid| {
            info.*.pid = pid;
        } else {
            return Errors.missing_pid;
        }
        var key: []const u8 = undefined;
        if (info.pathname) |pathname| {
            key = pathname;
        } else {
            // no pathname info get set to undefined name
            key = UNDEFINED_NAME;
        }
        const arr_op = self.collection.getPtr(key);
        if (arr_op) |arr| {
            try arr.append(info.*);
        } else {
            var arr: InfoList = .init(self.alloc);
            try arr.append(info.*);
            try self.collection.put(key, arr);
        }
    }

    /// Clear the process ID.
    fn clear_pid(self: *Manager) void {
        if (self.pid != null) {
            self.alloc.free(self.map_filename);
            self.pid = null;
        }
    }

    /// Clear the collection.
    fn clear_collection(self: *Manager) void {
        var vit = self.collection.valueIterator();
        while (vit.next()) |value| {
            for (value.items) |*entry| {
                entry.*.deinit();
            }
            value.*.deinit();
        }
        self.collection.clearRetainingCapacity();
    }
};

// ---------------------------------------------
// Testing
// ---------------------------------------------

const testing = std.testing;

//test "parse info one line with new line, program read/private" {
//    const expected_pathname: []const u8 = "/home/user/main";
//    const value: []const u8 = "5a4b2d4fd000-5a4b2d4fe000 r--p 00000000 08:30 432226                     /home/user/main\n";
//    var parser: ParseInfo = .init(testing.allocator);
//    const result = try parser.parse(value, 0);
//    try testing.expect(result.info != null);
//    var info: Info = result.info.?;
//    defer info.deinit();
//    try testing.expectEqual(value.len, result.bytes_read);
//    try testing.expectEqual(ParseStep.done, result.step);
//    try testing.expectEqual(info.start_addr, 99278929252352);
//    try testing.expectEqual(info.end_addr, 99278929256448);
//    try testing.expect(Permissions.read.check_perm(info.perm));
//    try testing.expect(Permissions.write.check_perm(info.perm) == false);
//    try testing.expect(Permissions.execute.check_perm(info.perm) == false);
//    try testing.expect(Permissions.shared.check_perm(info.perm) == false);
//    try testing.expectEqual(info.dev_major, 8);
//    try testing.expectEqual(info.dev_minor, 48);
//    try testing.expectEqual(info.inode, 432226);
//    try testing.expect(info.pathname != null);
//    try testing.expectEqualStrings(expected_pathname, info.pathname.?);
//}
//
//test "parse info one line with new line, heap read/write/private" {
//    const expected_pathname: []const u8 = "[heap]";
//    const value: []const u8 = "5a4b3200b000-5a4b3202c000 rw-p 00000000 00:00 0                          [heap]\n";
//    var parser: ParseInfo = .init(testing.allocator);
//    const result = try parser.parse(value, 0);
//    try testing.expect(result.info != null);
//    var info: Info = result.info.?;
//    defer info.deinit();
//    try testing.expectEqual(value.len, result.bytes_read);
//    try testing.expectEqual(ParseStep.done, result.step);
//    try testing.expectEqual(info.start_addr, 99279007952896);
//    try testing.expectEqual(info.end_addr, 99279008088064);
//    try testing.expect(Permissions.read.check_perm(info.perm));
//    try testing.expect(Permissions.write.check_perm(info.perm));
//    try testing.expect(Permissions.execute.check_perm(info.perm) == false);
//    try testing.expect(Permissions.shared.check_perm(info.perm) == false);
//    try testing.expectEqual(info.dev_major, 0);
//    try testing.expectEqual(info.dev_minor, 0);
//    try testing.expectEqual(info.inode, 0);
//    try testing.expect(info.pathname != null);
//    try testing.expectEqualStrings(expected_pathname, info.pathname.?);
//}
//
//test "parse info one line with new line, lib read/execute/shared" {
//    const expected_pathname: []const u8 = "/usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2";
//    const value: []const u8 = "7a837500e000-7a8375039000 r-xs 00001000 08:30 39741                      /usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2\n";
//    var parser: ParseInfo = .init(testing.allocator);
//    const result = try parser.parse(value, 0);
//    try testing.expect(result.info != null);
//    var info: Info = result.info.?;
//    defer info.deinit();
//    try testing.expectEqual(value.len, result.bytes_read);
//    try testing.expectEqual(ParseStep.done, result.step);
//    try testing.expectEqual(info.start_addr, 134705022296064);
//    try testing.expectEqual(info.end_addr, 134705022472192);
//    try testing.expect(Permissions.read.check_perm(info.perm));
//    try testing.expect(Permissions.write.check_perm(info.perm) == false);
//    try testing.expect(Permissions.execute.check_perm(info.perm));
//    try testing.expect(Permissions.shared.check_perm(info.perm));
//    try testing.expectEqual(info.dev_major, 8);
//    try testing.expectEqual(info.dev_minor, 48);
//    try testing.expectEqual(info.inode, 39741);
//    try testing.expect(info.pathname != null);
//    try testing.expectEqualStrings(expected_pathname, info.pathname.?);
//}
//
//test "parse info one line with new line, no pathname read/execute/shared" {
//    const value: []const u8 = "7a837500e000-7a8375039000 r-xs 00001000 00:00 0\n";
//    var parser: ParseInfo = .init(testing.allocator);
//    const result = try parser.parse(value, 0);
//    try testing.expect(result.info != null);
//    var info: Info = result.info.?;
//    defer info.deinit();
//    try testing.expectEqual(value.len, result.bytes_read);
//    try testing.expectEqual(ParseStep.done, result.step);
//    try testing.expectEqual(info.start_addr, 134705022296064);
//    try testing.expectEqual(info.end_addr, 134705022472192);
//    try testing.expect(Permissions.read.check_perm(info.perm));
//    try testing.expect(Permissions.write.check_perm(info.perm) == false);
//    try testing.expect(Permissions.execute.check_perm(info.perm));
//    try testing.expect(Permissions.shared.check_perm(info.perm));
//    try testing.expectEqual(info.dev_major, 0);
//    try testing.expectEqual(info.dev_minor, 0);
//    try testing.expectEqual(info.inode, 0);
//    try testing.expect(info.pathname != null);
//    // sets to undefined name
//    try testing.expectEqualStrings(UNDEFINED_NAME, info.pathname.?);
//}
//
//test "parse info single line with no new line" {
//    const expected_pathname: []const u8 = "/home/user/main";
//    const value: []const u8 = "5a4b2d4fd000-5a4b2d4fe000 r--p 00000000 08:30 432226                     /home/user/main";
//    var parser: ParseInfo = .init(testing.allocator);
//    const result = try parser.parse(value, 0);
//    try testing.expectEqual(ParseStep.process, result.step);
//    try testing.expect(result.info == null);
//
//    // we have to flush the last working object since there was no newline
//    const info_op = try parser.flush_last();
//    try testing.expect(info_op != null);
//    var info: Info = info_op.?;
//    defer info.deinit();
//
//    try testing.expectEqual(value.len, result.bytes_read);
//    try testing.expectEqual(info.start_addr, 99278929252352);
//    try testing.expectEqual(info.end_addr, 99278929256448);
//    try testing.expect(Permissions.read.check_perm(info.perm));
//    try testing.expect(Permissions.write.check_perm(info.perm) == false);
//    try testing.expect(Permissions.execute.check_perm(info.perm) == false);
//    try testing.expect(Permissions.shared.check_perm(info.perm) == false);
//    try testing.expectEqual(info.dev_major, 8);
//    try testing.expectEqual(info.dev_minor, 48);
//    try testing.expectEqual(info.inode, 432226);
//    try testing.expect(info.pathname != null);
//    try testing.expectEqualStrings(expected_pathname, info.pathname.?);
//}
//
//test "parse partial line" {
//    const value: []const u8 = "5a4b2d4fd000-5a4b2d4fe000";
//    var parser: ParseInfo = .init(testing.allocator);
//    const result = try parser.parse(value, 0);
//    try testing.expectEqual(ParseStep.end_addr, result.step);
//    try testing.expectEqual(value.len, result.bytes_read);
//    const empty = try parser.flush_last();
//    try testing.expect(empty == null);
//}
//
//test "Manager parse all entries" {
//    var manager: Manager = .init(testing.allocator);
//    defer manager.deinit();
//
//    const buffer: []const u8 =
//        \\5a4b2d4fd000-5a4b2d4fe000 r--p 00000000 08:30 432226                     /home/user/main
//        \\5a4b3200b000-5a4b3202c000 rw-p 00000000 00:00 0                          [heap]
//        \\7a837500e000-7a8375039000 r-xs 00001000 00:00 0
//    ;
//
//    const n = try manager.load_from_buffer(buffer, 0, true);
//
//    try testing.expectEqual(buffer.len, n);
//    try testing.expect(manager.collection.get("/home/user/main") != null);
//    try testing.expect(manager.collection.get("[heap]") != null);
//    try testing.expect(manager.collection.get(UNDEFINED_NAME) != null);
//    try testing.expect(manager.collection.get("does not exist") == null);
//    // TODO test grabbing entries
//}
