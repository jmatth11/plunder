const std = @import("std");
const common = @import("common.zig");

pub const Errors = error{
    pid_not_set,
};

pub const ProcInfo = struct {
    alloc: std.mem.Allocator,
    pid: ?usize,
    command: []const u8,
    command_line: common.StringView,
    environment_vars: common.StringView,

    pub fn init(alloc: std.mem.Allocator, pid: usize) !ProcInfo {
        var result: ProcInfo = .{
            .alloc = alloc,
            .pid = pid,
            .command = undefined,
            .command_line = undefined,
            .environment_vars = undefined,
        };
        try result.get_comm();
        try result.get_command_line();
        try result.get_environment_vars();
        return result;
    }

    pub fn deinit(self: *ProcInfo) void {
        if (self.pid != null) {
            self.alloc.free(self.command);
            self.alloc.free(self.command_line.ref);
            self.alloc.free(self.environment_vars.ref);
            self.pid = null;
        }
    }

    fn get_comm(self: *ProcInfo) !void {
        if (self.pid) |pid| {
            const file_path = try std.fmt.allocPrint(
                self.alloc,
                "/proc/{}/comm",
                .{pid},
            );
            defer self.alloc.free(file_path);
            self.command = try get_single_line_file(self.alloc, file_path, '\n');
            std.log.debug("command={s}", .{self.command});
        } else {
            return Errors.pid_not_set;
        }
    }

    fn get_command_line(self: *ProcInfo) !void {
        if (self.pid) |pid| {
            const file_path = try std.fmt.allocPrint(
                self.alloc,
                "/proc/{}/cmdline",
                .{pid},
            );
            defer self.alloc.free(file_path);
            const line = try get_single_line_file(self.alloc, file_path, '\n');
            self.command_line = .init(line, 0);
        } else {
            return Errors.pid_not_set;
        }
    }
    fn get_environment_vars(self: *ProcInfo) !void {
        if (self.pid) |pid| {
            const file_path = try std.fmt.allocPrint(
                self.alloc,
                "/proc/{}/environ",
                .{pid},
            );
            defer self.alloc.free(file_path);
            const line = try get_single_line_file(self.alloc, file_path, '\n');
            self.environment_vars = .init(line, 0);
        } else {
            return Errors.pid_not_set;
        }
    }
};

/// This function assumes the file being opened is a single line file (i.e. comm, cmdline, environ)
fn get_single_line_file(alloc: std.mem.Allocator, filename: []const u8, delimiter: u8) ![]const u8 {
    std.log.debug("filename = {s}", .{filename});
    var fs = try std.fs.openFileAbsolute(filename, .{});
    defer fs.close();
    var read_buf: [1024]u8 = undefined;
    var reader = fs.reader(&read_buf);
    var writer: std.io.Writer.Allocating = .init(alloc);
    errdefer writer.deinit();
    _ = try reader.interface.streamDelimiterEnding(&writer.writer, delimiter);
    const line = try writer.toOwnedSlice();
    errdefer alloc.free(line);
    return line;
}

pub const ProcInfoList = std.array_list.Managed(ProcInfo);

pub const ProcList = struct {
    alloc: std.heap.ArenaAllocator,
    procs: ProcInfoList,

    pub fn init(alloc: std.mem.Allocator) ProcList {
        return .{
            .alloc = .init(alloc),
            .procs = .init(alloc),
        };
    }

    pub fn add(self: *ProcList, pid: []const u8) !void {
        std.log.debug("ProcList.add({s})", .{pid});
        var proc: ProcInfo = try .init(
            self.alloc.allocator(),
            try std.fmt.parseInt(usize, pid, 10),
        );
        errdefer proc.deinit();
        try self.procs.append(proc);
    }

    pub fn deinit(self: *ProcList) void {
        self.alloc.deinit();
        self.procs.deinit();
    }
};

pub fn get_processes(alloc: std.mem.Allocator) !ProcList {
    const dir = try std.fs.openDirAbsolute("/proc", .{
        .iterate = true,
        .access_sub_paths = false,
        .no_follow = true,
    });
    var it = dir.iterate();
    var result: ProcList = .init(alloc);
    errdefer result.deinit();
    while (try it.next()) |entry| {
        if (all_digits(entry.name)) {
            try result.add(entry.name);
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
