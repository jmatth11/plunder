const std = @import("std");
const tui = @import("zigtui");
const procView = @import("tui/ProcView.zig");
const memoryView = @import("tui/MemoryView.zig");
const errorView = @import("tui/ErrorView.zig");
const theme = tui.themes.dracula;

const ErrorMessage = struct {
    msg: []const u8,
};

const View = struct {
    focus: usize = 0,
    err: ?ErrorMessage = null,

    error_view: *errorView.ErrorView,
    error_last_shown: i64 = 0,
    error_msg: ?[]const u8 = null,
    procColumn: procView.ProcView,
    memView: memoryView.MemoryView,

    pub fn deselect(self: *View) void {
        switch (self.focus) {
            0 => {},
            1 => {
                self.memView.deselect();
            },
            else => {},
        }
    }

    pub fn select(self: *View) !void {
        switch (self.focus) {
            0 => {
                try self.memView.set_proc(try self.procColumn.get_selected());
                self.change_focus();
            },
            1 => {
                try self.memView.select();
            },
            else => {},
        }
    }
    pub fn change_focus(self: *View) void {
        self.focus += 1;
        self.focus = self.focus % 2;
        switch (self.focus) {
            0 => {
                self.procColumn.focused = true;
                self.memView.focused = false;
            },
            1 => {
                self.procColumn.focused = false;
                self.memView.focused = true;
            },
            else => {},
        }
    }

    pub fn next_selection(self: *View) void {
        switch (self.focus) {
            0 => {
                self.procColumn.next_selection();
            },
            1 => {
                self.memView.next_selection();
            },
            else => {},
        }
    }
    pub fn prev_selection(self: *View) void {
        switch (self.focus) {
            0 => {
                self.procColumn.prev_selection();
            },
            1 => {
                self.memView.prev_selection();
            },
            else => {},
        }
    }
};

pub fn main() !void {
    //var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    //defer _ = gpa.deinit();
    const allocator = std.heap.smp_allocator;

    var backend = try tui.backend.init(allocator);
    defer backend.deinit();

    var terminal = try tui.terminal.Terminal.init(allocator, backend.interface());
    defer terminal.deinit();

    try terminal.hideCursor();
    defer terminal.showCursor() catch {};

    var error_view = try errorView.get_error_view();
    defer error_view.destroy();

    var cur_view: View = .{
        .procColumn = .init(allocator),
        .memView = .init(allocator),
        .error_view = try errorView.get_error_view(),
    };
    defer cur_view.procColumn.deinit();
    var running = true;
    while (running) {
        const event = try backend.interface().pollEvent(100);
        switch (event) {
            .key => |key| {
                switch (key.code) {
                    .char => |c| {
                        if (c == 'q' or c == 'Q') running = false;
                        if (c == 'j') cur_view.next_selection();
                        if (c == 'k') cur_view.prev_selection();
                        if (c == 'b') cur_view.deselect();
                    },
                    .tab => {
                        cur_view.change_focus();
                    },
                    .up => {
                        cur_view.prev_selection();
                    },
                    .down => {
                        cur_view.next_selection();
                    },
                    .enter => {
                        try cur_view.select();
                    },
                    .esc => running = false,
                    else => {},
                }
            },
            .resize => |size| {
                try terminal.resize(.{ .width = size.width, .height = size.height });
            },
            else => {},
        }
        try terminal.draw(&cur_view, struct {
            fn render(view: *View, buf: *tui.render.Buffer) anyerror!void {
                const area = buf.getArea();
                const inner = tui.Rect{
                    .x = area.x + 1,
                    .y = area.y + 1,
                    .width = area.width -| 2,
                    .height = area.height -| 2,
                };
                const block: tui.widgets.Block = .{
                    .title = "Plunder — 'q' for quit; j/k for down/up; tab to switch windows",
                    .style = theme.baseStyle(),
                    .borders = tui.widgets.Borders.all(),
                    .border_style = theme.borderFocusedStyle(),
                    .border_symbols = tui.widgets.BorderSymbols.rounded(),
                };
                block.render(area, buf);

                // handle display error
                if (view.err) |err| {
                    const warn: tui.widgets.Paragraph = .{
                        .style = theme.errorStyle(),
                        .text = err.msg,
                    };
                    warn.render(inner, buf);
                    return;
                }

                var table_area = inner;
                table_area.width = @intFromFloat(@floor(@as(f32, @floatFromInt(inner.width)) * 0.3));
                view.procColumn.render(table_area, buf) catch |err| {
                    if (err == error.AccessDenied) {
                        view.err = .{ .msg = "Could not read processes. Try running with 'sudo'." };
                        return;
                    } else {
                        return err;
                    }
                };

                var view_area = inner;
                view_area.x += table_area.width;
                view_area.width = view_area.width -| table_area.width;
                try view.memView.render(view_area, buf);
                const now = std.time.milliTimestamp();
                const diff_time = now - view.error_last_shown;
                if (diff_time >= std.time.ms_per_s * 5) {
                    if (view.error_msg) |msg| {
                        view.error_view.free_msg(msg);
                    }
                    view.error_msg = view.error_view.pop();
                    if (view.error_msg != null) {
                        view.error_last_shown = std.time.milliTimestamp();
                    }
                }
                if (view.error_msg) |err_msg| {
                    const error_block: tui.widgets.Block = .{
                        .title = "Error",
                        .title_style = theme.errorStyle(),
                        .border_symbols = tui.widgets.BorderSymbols.double(),
                        .border_style = theme.borderFocusedStyle(),
                        .borders = tui.widgets.Borders.all(),
                        .style = theme.baseStyle(),
                    };
                    var top_right_area = area;
                    top_right_area.x = top_right_area.width - 50;
                    top_right_area.width = 50;
                    top_right_area.height = 6;
                    error_block.render(top_right_area, buf);
                    const inner_error_block = error_block.inner(top_right_area);
                    const err_paragraph: tui.widgets.Paragraph = .{
                        .text = err_msg,
                        .style = theme.errorStyle(),
                    };
                    err_paragraph.render(inner_error_block, buf);
                }
            }
        }.render);
    }
}
