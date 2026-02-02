const std = @import("std");
const tui = @import("zigtui");
const procView = @import("tui/ProcView.zig");
const memoryView = @import("tui/MemoryView.zig");
const errorView = @import("tui/ErrorView.zig");
const infoView = @import("tui/InfoView.zig");
const searchBar = @import("tui/SearchBar.zig");
const editMemoryView = @import("tui/EditMemory.zig");
const theme = tui.themes.dracula;

/// Specific error message for top level "show-stopper" errors.
const ErrorMessage = struct {
    msg: []const u8,
};

/// Main view structure for the TUI.
const View = struct {
    /// Main allocator
    alloc: std.mem.Allocator,
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

    /// Flag for running loop.
    running: bool = true,
    /// Flag to show the info view.
    show_info: bool = false,
    /// Flag for search mode (allows user to filter the current view)
    search_mode: bool = false,
    /// Flag for visual mode actions.
    visual_mode: bool = false,

    // other views

    /// Proccess Column view -- List of all processes on machine.
    procColumn: procView.ProcView,
    /// Memory view -- Handles showing memory regions and memory for a process.
    memView: memoryView.MemoryView,
    /// Info view -- Handles showing the process basic information.
    info_view: infoView.InfoView,
    /// SearchBar view -- Handles filter lists of the focused window.
    search_bar: searchBar.SearchBar,
    /// Edit Memory View -- Handles the memory editor.
    edit_memory_view: editMemoryView.EditMemoryView,

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
            1 => {
                if (self.memView.memory_loaded()) {
                    const search_term = try self.search_bar.get_result();
                    if (search_term) |term| {
                        if (self.memView.memory_search(term)) {
                            self.visual_mode = true;
                        } else {
                            try self.error_view.add("Search term could not be found.");
                        }
                    }
                    // don't close search window because we could want to keep searching
                }
            },
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
                    self.visual_mode = false;
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

    pub fn visual_select(self: *View) !void {
        switch (self.focus) {
            1 => {
                if (self.visual_mode) {
                    if (self.memView.get_mutable_memory()) |memory| {
                        if (memory) |mem| {
                            self.edit_memory_view.load(mem);
                        }
                    } else |err| {
                        const msg = try std.fmt.allocPrint(
                            self.alloc,
                            "Error with getting mutable memory: {any}\n",
                            .{err},
                        );
                        defer self.alloc.free(msg);
                        try self.error_view.add(msg);
                    }
                }
            },
            else => {},
        }
    }

    /// Write edited memory.
    pub fn write_memory(self: *View) !void {
        if (self.edit_memory_view.is_loaded()) {
            if (self.edit_memory_view.memory) |*memory| {
                self.memView.memory_write(memory.*) catch |err| {
                    const msg = try std.fmt.allocPrint(
                        self.alloc,
                        "Error writing memory: {any}\n",
                        .{err},
                    );
                    defer self.alloc.free(msg);
                    try self.error_view.add(msg);
                };
                self.edit_memory_view.unload();
            }
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
            0 => {},
            1 => {
                if (self.edit_memory_view.is_loaded()) {
                    self.edit_memory_view.nav(.right);
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
            0 => {},
            1 => {
                if (self.edit_memory_view.is_loaded()) {
                    self.edit_memory_view.nav(.left);
                } else {
                    self.memView.prev_selection();
                }
            },
            else => {},
        }
    }

    /// Up selection action
    pub fn up_selection(self: *View) void {
        switch (self.focus) {
            0 => {
                // for procColumn prev/next is up/down
                self.procColumn.prev_selection();
            },
            1 => {
                if (self.edit_memory_view.is_loaded()) {
                    self.edit_memory_view.nav(.up);
                } else if (self.show_info) {
                    self.info_view.prev_selection();
                } else {
                    self.memView.up_selection();
                }
            },
            else => {},
        }
    }
    /// Down selection action
    pub fn down_selection(self: *View) void {
        switch (self.focus) {
            0 => {
                // for procColumn prev/next is up/down
                self.procColumn.next_selection();
            },
            1 => {
                if (self.edit_memory_view.is_loaded()) {
                    self.edit_memory_view.nav(.down);
                } else if (self.show_info) {
                    self.info_view.next_selection();
                } else {
                    self.memView.down_selection();
                }
            },
            else => {},
        }
    }
    /// Visual selection action.
    pub fn visual_selection(self: *View) void {
        switch (self.focus) {
            0 => {},
            1 => {
                if (!self.edit_memory_view.is_loaded()) {
                    self.memView.memory_visual_selection();
                    self.visual_mode = !self.visual_mode;
                }
            },
            else => {},
        }
    }

    pub fn toggle_search_mode(self: *View) void {
        switch (self.focus) {
            0 => {
                self.search_mode = true;
                // reset search text
                self.search_bar.len = 0;
            },
            1 => {
                if (self.memView.memory_loaded()) {
                    self.search_mode = true;
                    self.search_bar.len = 0;
                }
            },
            else => {},
        }
    }

    /// Key handler
    pub fn key_handler(self: *View, c: u21) void {
        if (self.search_mode) {
            self.search_bar.add(c);
        } else if (self.edit_memory_view.is_loaded()) {
            self.edit_memory_view.add_character(c) catch {};
        } else {
            if (c == 'q' or c == 'Q') self.running = false;
            if (c == 'j') self.down_selection();
            if (c == 'k') self.up_selection();
            if (c == 'h') self.prev_selection();
            if (c == 'l') self.next_selection();
            if (c == 'b') self.deselect();
            if (c == 'i') {
                self.show_info = !self.show_info;
                self.visual_mode = false;
            }
            if (c == '/') self.toggle_search_mode();
            if (c == 'v') self.visual_selection();
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
        .alloc = allocator,
        .procColumn = .init(allocator),
        .memView = .init(allocator),
        .info_view = .init(allocator),
        .search_bar = .init(allocator),
        .error_view = try errorView.get_error_view(),
        .edit_memory_view = .init(allocator),
    };
    defer cur_view.deinit();

    // main loop
    while (cur_view.running) {
        // poll every 100 milliseconds
        const event = try backend.interface().pollEvent(100);
        // handle key events
        switch (event) {
            .key => |key| {
                switch (key.code) {
                    .char => |c| {
                        cur_view.key_handler(c);
                    },
                    .backspace => {
                        if (cur_view.search_mode) {
                            cur_view.search_bar.delete();
                        } else if (cur_view.edit_memory_view.is_loaded()) {
                            cur_view.edit_memory_view.delete_character();
                        }
                    },
                    .tab => {
                        if (cur_view.edit_memory_view.is_loaded()) {
                            cur_view.edit_memory_view.toggle_entry_mode();
                        } else if (!cur_view.search_mode) {
                            cur_view.change_focus();
                        }
                    },
                    .up => {
                        if (cur_view.edit_memory_view.is_loaded()) {
                            cur_view.edit_memory_view.nav(.up);
                        } else if (!cur_view.search_mode) {
                            cur_view.prev_selection();
                        }
                    },
                    .down => {
                        if (cur_view.edit_memory_view.is_loaded()) {
                            cur_view.edit_memory_view.nav(.down);
                        } else if (!cur_view.search_mode) {
                            cur_view.next_selection();
                        }
                    },
                    .left => {
                        if (cur_view.edit_memory_view.is_loaded()) {
                            cur_view.edit_memory_view.nav(.left);
                        }
                    },
                    .right => {
                        if (cur_view.edit_memory_view.is_loaded()) {
                            cur_view.edit_memory_view.nav(.right);
                        }
                    },
                    .enter => {
                        if (cur_view.edit_memory_view.is_loaded()) {
                            try cur_view.write_memory();
                        } else if (cur_view.visual_mode) {
                            try cur_view.visual_select();
                        } else if (cur_view.search_mode) {
                            try cur_view.set_filter();
                        } else {
                            try cur_view.select();
                        }
                    },
                    .esc => {
                        if (cur_view.edit_memory_view.is_loaded()) {
                            cur_view.edit_memory_view.unload();
                        } else if (cur_view.search_mode) {
                            cur_view.search_mode = false;
                        } else {
                            cur_view.running = false;
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

                if (view.edit_memory_view.is_loaded()) {
                    const start_x: u16 = @intFromFloat(@as(f32, @floatFromInt(area.width)) * 0.2);
                    const start_y: u16 = @intFromFloat(@as(f32, @floatFromInt(area.height)) * 0.2);
                    const edit_memory_area: tui.Rect = .{
                        .x = start_x,
                        .y = start_y,
                        .width = area.width - (start_x * 2),
                        .height = area.height - (start_y * 2),
                    };
                    try view.edit_memory_view.render(edit_memory_area, buf);
                }

                // present last to show on top of everything.
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
                    buf.fillArea(inner_error_block, ' ', theme.baseStyle());
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
