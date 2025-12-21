const std = @import("std");

pub const StringList = std.array_list.Managed([]const u8);

pub const ProcList = struct {
    alloc: std.mem.Allocator,
    procs: StringList,

    pub fn init(alloc: std.mem.Allocator) ProcList {
        return .{
            .alloc = alloc,
            .procs = .init(alloc),
        };
    }

    pub fn add(self: *ProcList, entry: []const u8) !void {
        try self.procs.append(try self.alloc.dupe(u8, entry));
    }

    pub fn deinit(self: *ProcList) void {
        for (self.procs.items) |item| {
            self.alloc.free(item);
        }
        self.procs.deinit();
    }
};

pub fn get_processes(alloc: std.mem.Allocator) !ProcList {
    const dir = try std.fs.openDirAbsolute("/proc", .{ });
    var walk = try dir.walk(alloc);
    defer walk.deinit();
    var result: ProcList = .init(alloc);
    while (try walk.next()) |entry| {
        if (all_digits(entry.basename)) {
            try result.add(entry.basename);
        }
    }
    return result;
}

fn all_digits(key: []const u8) bool {
    for (key) |char| {
        if (!std.ascii.isDigit(char)) {
            return false;
        }
    }
    return true;
}
