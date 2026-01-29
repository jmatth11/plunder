const std = @import("std");

/// Messages type is an array list of strings.
const Messages = std.array_list.Managed([]const u8);

/// ErrorView structure, controls storing and popping error messages to be
/// seen.
pub const ErrorView = struct {
    /// main allocator
    alloc: std.mem.Allocator,
    /// List of messages
    msgs: Messages,

    /// Create and allocated instance
    pub fn create(alloc: std.mem.Allocator) !*ErrorView {
        var result = try alloc.create(ErrorView);
        result.alloc = alloc;
        result.msgs = .init(alloc);
        return result;
    }

    /// Add a message to be shown
    pub fn add(self: *ErrorView, msg: []const u8) !void {
        try self.msgs.append(try self.alloc.dupe(u8, msg));
    }

    /// Pop the next message off the list.
    /// The returned string must be freed with free_msg
    pub fn pop(self: *ErrorView) ?[]const u8 {
        return self.msgs.pop();
    }

    /// Free the message.
    pub fn free_msg(self: *ErrorView, msg: []const u8) void {
        self.alloc.free(msg);
    }

    /// Destroy the instance.
    pub fn destroy(self: *ErrorView) void {
        self.msgs.deinit();
        self.alloc.destroy(self);
    }
};

/// ErrorView singleton instance
var ErrorViewInstance: ?*ErrorView = null;

/// Get/Instantiate the singleton instance of an ErrorView.
pub fn get_error_view() !*ErrorView {
    if (ErrorViewInstance == null) {
        ErrorViewInstance = try ErrorView.create(std.heap.smp_allocator);
    }
    return ErrorViewInstance.?;
}
