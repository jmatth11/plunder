const std = @import("std");
const dvui = @import("dvui");
const plunder = @import("plunder");

pub const ProcView = struct {
    alloc: std.mem.Allocator,
    list: plunder.proc.ProcList,

    pub fn init(alloc: std.mem.Allocator) !ProcView {
        const result: ProcView = .{
            .alloc = alloc,
            .list = try plunder.proc.get_processes(alloc),
        };
        return result;
    }

    pub fn frame() void {

    }

    pub fn deinit(self: *ProcView) void {
        self.list.deinit();
    }
};
