const std = @import("std");

/// Errors related to structures in common.zig
pub const Errors = error{
    out_of_bounds,
    delimiter_not_found,
};

/// Array list of strings
pub const StringList = std.array_list.Managed([]const u8);

/// Manager for String list type.
pub const StringListManager = struct {
    alloc: std.mem.Allocator,
    list: StringList,

    pub fn init(alloc: std.mem.Allocator) StringListManager {
        return .{
            .alloc = alloc,
            .list = .init(alloc),
        };
    }

    pub fn create(self: *StringListManager, alloc: std.mem.Allocator) void {
        self.alloc = alloc;
        self.list = .init(alloc);
    }

    pub fn add(self: *StringListManager, entry: []const u8) !void {
        try self.list.append(try self.alloc.dupe(u8, entry));
    }

    pub fn add_string_list(self: *StringListManager, list: StringList) !void {
        for (list.items) |entry| {
            try self.add(entry);
        }
    }

    pub fn deinit(self: *StringListManager) void {
        defer self.list.deinit();
        for (self.list.items) |entry| {
            self.alloc.free(entry);
        }
    }
};

/// String view structure.
/// Holds a const reference to a string and allows to use a delimiter
/// to view into the string in divided parts.
pub const StringView = struct {
    /// Reference to string
    ref: []const u8,
    /// Delimiter to use
    delimiter: u8,
    /// The length of the reference string.
    len: usize = 0,

    /// initialize
    pub fn init(ref: []const u8, delimiter: u8) StringView {
        var result: StringView = .{
            .ref = ref,
            .delimiter = delimiter,
        };
        result.len = result._len();
        return result;
    }

    /// View the portion of the string at the given index.
    pub fn at(self: *const StringView, idx: usize) ![]const u8 {
        if (idx > self.len) {
            return Errors.out_of_bounds;
        }
        // if there was no delimiter found return the whole string.
        if (self.len == 0) {
            return self.ref;
        }
        var ref_idx: usize = 0;
        var step: usize = 0;
        var start: usize = 0;
        while (ref_idx < self.ref.len) : (ref_idx += 1) {
            if (step == idx) {
                const end = std.mem.indexOfScalar(u8, self.ref[start..], self.delimiter);
                if (end == null) {
                    return Errors.delimiter_not_found;
                }
                return self.ref[start..(start + end.?)];
            }
            if (self.ref[ref_idx] == self.delimiter) {
                step += 1;
                start = ref_idx + 1;
            }
        }
        unreachable;
    }

    /// find how many segments of the string there are by the delimiter.
    fn _len(self: *StringView) usize {
        var idx: usize = 0;
        var count: usize = 0;
        while (idx < self.ref.len) : (idx += 1) {
            if (self.ref[idx] == self.delimiter) {
                count += 1;
            }
        }
        return count;
    }
};
