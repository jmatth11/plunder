const std = @import("std");
const tui = @import("zigtui");
const procView = @import("tui/ProcView.zig");
const memoryView = @import("tui/MemoryView.zig");
const errorView = @import("tui/ErrorView.zig");
const infoView = @import("tui/InfoView.zig");
const searchBar = @import("tui/SearchBar.zig");
const theme = tui.themes.dracula;

/// Specific error message for top level "show-stopper" errors.
const ErrorMessage = struct {
    msg: []const u8,
};

/// Main view structure for the TUI.
const View = struct {
    /// Window focus variable
    focus: usize = 0,
    /// show-stopper error message.
    err: ?ErrorMessage = null,

    /// Error view singleton for displaying errors that happen in subviews.
    error_view: *errorView.ErrorView,
    /// timestamp of last shown error
    error_last_shown: i64 = 0,
    /// error message currently being displayed
    error_msg: ?[]const u8 = null,

    /// Flag to show the info view.
    show_info: bool = false,

    /// Flag for search mode (allows user to filter the current view)
    search_mode: bool = false,

    // other views

    /// Proccess Column view -- List of all processes on machine.
    procColumn: procView.ProcView,
    /// Memory view -- Handles showing memory regions and memory for a process.
    memView: memoryView.MemoryView,
    /// Info view -- Handles showing the process basic information.
    info_view: infoView.InfoView,
    /// SearchBar view -- Handles filter lists of the focused window.
    search_bar: searchBar.SearchBar,

    pub fn deinit(self: *View) void {
        if (self.error_msg) |err_msg| {
            self.error_view.free_msg(err_msg);
            self.error_msg = null;
        }
        self.procColumn.deinit();
        self.memView.deinit();
        self.info_view.deinit();
    }

    /// Set search filter for focused window.
    pub fn set_filter(self: *View) !void {
        switch (self.focus) {
            0 => {
                const filter = try self.search_bar.get_result();
                try self.procColumn.set_filter(filter);
                self.search_mode = false;
            },
            1 => {},
            else => {},
        }
    }

    /// Clear search filter for focused window.
    pub fn clear_filter(self: *View) !void {
        switch (self.focus) {
            0 => {
                try self.procColumn.set_filter(null);
            },
            1 => {},
            else => {},
        }
    }

    /// Deselect action
    pub fn deselect(self: *View) void {
        switch (self.focus) {
            0 => {},
            1 => {
                if (!self.show_info) {
                    self.memView.deselect();
                }
            },
            else => {},
        }
    }

    /// Select action
    pub fn select(self: *View) !void {
        switch (self.focus) {
            0 => {
                const proc = try self.procColumn.get_selected();
                try self.memView.set_proc(proc);
                try self.info_view.load(proc);
                self.change_focus();
            },
            1 => {
                if (!self.show_info) {
                    try self.memView.select();
                }
            },
            else => {},
        }
    }

    /// Change focus to next view.
    pub fn change_focus(self: *View) void {
        self.focus += 1;
        self.focus = self.focus % 2;
        switch (self.focus) {
            0 => {
                self.procColumn.focused = true;
                self.info_view.focused = false;
                self.memView.focused = false;
            },
            1 => {
                self.procColumn.focused = false;
                self.info_view.focused = true;
                self.memView.focused = true;
            },
            else => {},
        }
    }

    /// Next selection action.
    pub fn next_selection(self: *View) void {
        switch (self.focus) {
            0 => {
                self.procColumn.next_selection();
            },
            1 => {
                if (self.show_info) {
                    self.info_view.next_selection();
                } else {
                    self.memView.next_selection();
                }
            },
            else => {},
        }
    }
    /// Previous selection action.
    pub fn prev_selection(self: *View) void {
        switch (self.focus) {
            0 => {
                self.procColumn.prev_selection();
            },
            1 => {
                if (self.show_info) {
                    self.info_view.prev_selection();
                } else {
                    self.memView.prev_selection();
                }
            },
            else => {},
        }
    }
};

pub fn main() !void {
    //var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    //defer _ = gpa.deinit();
    const allocator = std.heap.smp_allocator;

    // terminal setup
    var backend = try tui.backend.init(allocator);
    defer backend.deinit();
    var terminal = try tui.terminal.Terminal.init(allocator, backend.interface());
    defer terminal.deinit();
    try terminal.hideCursor();
    defer terminal.showCursor() catch {};

    // create error view singleton
    var error_view = try errorView.get_error_view();
    defer error_view.destroy();

    // instantiate our main view.
    var cur_view: View = .{
        .procColumn = .init(allocator),
        .memView = .init(allocator),
        .info_view = .init(allocator),
        .search_bar = .init(allocator),
        .error_view = try errorView.get_error_view(),
    };
    defer cur_view.deinit();

    // main loop
    var running = true;
    while (running) {
        // poll every 100 milliseconds
        const event = try backend.interface().pollEvent(100);
        // handle key events
        switch (event) {
            .key => |key| {
                switch (key.code) {
                    .char => |c| {
                        if (!cur_view.search_mode) {
                            if (c == 'q' or c == 'Q') running = false;
                            if (c == 'j') cur_view.next_selection();
                            if (c == 'k') cur_view.prev_selection();
                            if (c == 'b') cur_view.deselect();
                            if (c == 'i') {
                                cur_view.show_info = !cur_view.show_info;
                            }
                            if (c == '/') {
                                cur_view.search_mode = true;
                                // reset search text
                                cur_view.search_bar.len = 0;
                            }
                        } else {
                            cur_view.search_bar.add(c);
                        }
                    },
                    .backspace => {
                        if (cur_view.search_mode) {
                            cur_view.search_bar.delete();
                        }
                    },
                    .tab => {
                        if (!cur_view.search_mode) {
                            cur_view.change_focus();
                        }
                    },
                    .up => {
                        if (!cur_view.search_mode) {
                            cur_view.prev_selection();
                        }
                    },
                    .down => {
                        if (!cur_view.search_mode) {
                            cur_view.next_selection();
                        }
                    },
                    .enter => {
                        if (cur_view.search_mode) {
                            try cur_view.set_filter();
                        } else {
                            try cur_view.select();
                        }
                    },
                    .esc => {
                        if (cur_view.search_mode) {
                            cur_view.search_mode = false;
                        } else {
                            running = false;
                        }
                    },
                    else => {},
                }
            },
            .resize => |size| {
                try terminal.resize(.{ .width = size.width, .height = size.height });
            },
            else => {},
        }
        // draw terminal
        try terminal.draw(&cur_view, struct {
            fn render(view: *View, buf: *tui.render.Buffer) anyerror!void {
                const area = buf.getArea();
                const inner = tui.Rect{
                    .x = area.x + 1,
                    .y = area.y + 1,
                    .width = area.width -| 2,
                    .height = area.height -| 2,
                };
                // setup main block
                const block: tui.widgets.Block = .{
                    .title = " Plunder — [q] quit; [j/k] down/up; [tab] switch focus ",
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

                // render process column
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

                // render memory view
                var view_area = inner;
                view_area.x += table_area.width;
                view_area.width = view_area.width -| table_area.width;
                if (view.show_info) {
                    try view.info_view.render(view_area, buf);
                } else {
                    try view.memView.render(view_area, buf);
                }

                // render error messages
                const now = std.time.milliTimestamp();
                const diff_time = now - view.error_last_shown;
                // clear after 5 seconds
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
                if (view.search_mode) {
                    const search_bar_area: tui.Rect = .{
                        .x = inner.x,
                        .y = inner.height - 1,
                        .height = 3,
                        .width = inner.width,
                    };
                    try view.search_bar.render(search_bar_area, buf);
                }
            }
        }.render);
    }
}
