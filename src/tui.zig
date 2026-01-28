const std = @import("std");
const tui = @import("zigtui");
const procView = @import("tui/ProcView.zig");
const memoryView = @import("tui/MemoryView.zig");
const theme = tui.themes.dracula;

const ErrorMessage = struct {
    msg: []const u8,
};

const View = struct {
    focus: usize = 0,
    err: ?ErrorMessage = null,
    procColumn: procView.ProcView,
    memView: memoryView.MemoryView,

    pub fn deselect(self: *View) void {
        switch (self.focus) {
            0 => {
            },
            1 => {
                self.memView.deselect();
            },
            else => {}
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
            else => {}
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
            else => {}
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
            else => {}
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
            else => {}
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

    var cur_view: View = .{
        .procColumn = .init(allocator),
        .memView = .init(allocator),
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
                    .title = "Plunder — press 'q' to quit",
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

            }
        }.render);
    }
}
