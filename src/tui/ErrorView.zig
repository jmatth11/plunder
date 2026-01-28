const std = @import("std");

const Messages = std.array_list.Managed([]const u8);

pub const ErrorView = struct {
    alloc: std.mem.Allocator,
    msgs: Messages,

    pub fn create(alloc: std.mem.Allocator) !*ErrorView {
        var result = try alloc.create(ErrorView);
        result.alloc = alloc;
        result.msgs = .init(alloc);
        return result;
    }

    pub fn add(self: *ErrorView, msg: []const u8) !void {
        try self.msgs.append(try self.alloc.dupe(u8, msg));
    }

    pub fn pop(self: *ErrorView) ?[]const u8 {
        return self.msgs.pop();
    }

    pub fn free_msg(self: *ErrorView, msg: []const u8) void {
        self.alloc.free(msg);
    }

    pub fn destroy(self: *ErrorView) void {
        self.msgs.deinit();
        self.alloc.destroy(self);
    }
};

var ErrorViewInstance: ?*ErrorView = null;

pub fn get_error_view() !*ErrorView {
    if (ErrorViewInstance == null) {
        ErrorViewInstance = try ErrorView.create(std.heap.smp_allocator);
    }
    return ErrorViewInstance.?;
}
