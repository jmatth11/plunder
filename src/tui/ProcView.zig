const std = @import("std");
const plunder = @import("plunder");
const tui = @import("zigtui");

/// Errors related to Process View
pub const Errors = error{
    uninitialized_procs,
};

/// Main process view structure.
pub const ProcView = struct {
    /// regular allocator
    alloc: std.mem.Allocator,
    /// arena allocator
    arena: std.heap.ArenaAllocator,
    /// list of processes
    procs: ?plunder.proc.ProcList = null,
    /// main theme
    theme: tui.Theme = tui.themes.dracula,
    /// generated rows for process table
    rows: ?[]tui.widgets.Row = null,
    /// col headers for process table
    cols: []const tui.widgets.Column,
    /// currently selected item
    selected: usize = 0,
    /// scroll offset in table
    scroll_offset: usize = 0,
    /// flag for focus (controlled by parent)
    focused: bool = true,
    /// Filter string for process list.
    filter: ?[]const u8 = null,

    /// initialize the process view
    pub fn init(alloc: std.mem.Allocator) ProcView {
        const result: ProcView = .{
            .alloc = alloc,
            .arena = .init(alloc),
            .cols = &.{
                .{
                    .header = "ID",
                },
                .{
                    .header = "Command",
                },
            },
        };
        return result;
    }

    /// Main render function for process view
    pub fn render(self: *ProcView, area: tui.Rect, buf: *tui.render.Buffer) !void {
        // create containing block
        const block: tui.widgets.Block = .{
            .style = self.theme.baseStyle(),
            .borders = tui.widgets.Borders.all(),
            .border_symbols = tui.widgets.BorderSymbols.double(),
            .border_style = if (self.focused) self.theme.borderFocusedStyle() else self.theme.borderStyle(),
            .title = " Process List - [/] search ",
        };

        block.render(area, buf);

        // generate rows
        try self.gen_rows();

        // get inner area for the table
        const inner_block = block.inner(area);
        // figure out offset position
        const offset_height = inner_block.height - 2;
        const scroll_offset_height = self.scroll_offset + offset_height;
        if (self.selected > scroll_offset_height) {
            self.scroll_offset = self.selected - offset_height;
        } else if (self.selected < self.scroll_offset) {
            self.scroll_offset = self.selected;
        }
        // TODO see if we can increase the Command column size to fill up the remaining width
        const table: tui.widgets.Table = .{
            .columns = self.cols,
            .header_style = self.theme.tableHeaderStyle(),
            .rows = self.rows.?,
            .selected_style = self.theme.selectionStyle(),
            .selected = self.selected,
            .offset = self.scroll_offset,
        };
        table.render(inner_block, buf);
    }

    /// Get the selected item in the process table
    pub fn get_selected(self: *ProcView) Errors!plunder.proc.ProcInfo {
        if (self.procs) |procs| {
            return procs.procs.items[self.selected];
        }
        return Errors.uninitialized_procs;
    }

    /// Next selection action
    pub fn next_selection(self: *ProcView) void {
        if (self.rows) |rows| {
            self.selected += 1;
            self.selected = self.selected % rows.len;
        }
    }
    /// Previous selection action
    pub fn prev_selection(self: *ProcView) void {
        if (self.rows) |rows| {
            if (self.selected == 0) {
                self.selected = rows.len - 1;
            } else {
                self.selected -= 1;
            }
        }
    }

    /// Set the filter to apply to the process list.
    pub fn set_filter(self: *ProcView, new_filter: ?[]const u8) !void {
        if (self.filter) |filter| {
            self.alloc.free(filter);
        }
        self.filter = new_filter;
        if (self.filter) |filter| {
            self.filter = try self.alloc.dupe(u8, filter);
        }
        self.clear_rows();
        self.clear_procs();
    }

    /// Cleanup
    pub fn deinit(self: *ProcView) void {
        self.arena.deinit();
        if (self.rows) |rows| {
            self.alloc.free(rows);
            self.rows = null;
        }
    }

    fn clear_procs(self: *ProcView) void {
        if (self.procs) |*procs| {
            procs.*.deinit();
            self.procs = null;
        }
    }

    fn clear_rows(self: *ProcView) void {
        if (self.rows) |rows| {
            _ = self.arena.reset(.free_all);
            self.alloc.free(rows);
            self.rows = null;
            self.selected = 0;
            self.scroll_offset = 0;
        }
    }

    /// Generate rows for the table
    fn gen_rows(self: *ProcView) !void {
        if (self.rows == null) {
            var procs_list = try plunder.proc.get_processes(self.alloc);
            errdefer procs_list.deinit();
            var result_procs: plunder.proc.ProcList = .init(self.alloc);
            errdefer result_procs.deinit();
            var count: usize = 0;
            var row_list: std.array_list.Managed(tui.widgets.Row) = .init(self.alloc);
            defer row_list.deinit();
            for (procs_list.procs.items) |proc| {
                // use arena allocator so we can bulk cleanup every frame
                const pid_str: []const u8 = try std.fmt.allocPrint(
                    self.arena.allocator(),
                    "{}",
                    .{proc.pid.?},
                );
                const command: []const u8 = try self.arena.allocator().dupe(
                    u8,
                    proc.command,
                );
                var should_add: bool = true;
                if (self.filter) |filter| {
                    const pid_check = std.mem.containsAtLeast(u8, pid_str, 1, filter);
                    const command_check = std.mem.containsAtLeast(u8, command, 1, filter);
                    should_add = pid_check or command_check;
                }
                if (should_add) {
                    const cells = try self.arena.allocator().alloc([]const u8, 2);
                    cells[0] = pid_str;
                    cells[1] = command;
                    const row: tui.widgets.Row = .{
                        .style = self.theme.tableRowStyle(count, false),
                        .cells = cells,
                    };
                    try row_list.append(row);
                    try result_procs.append(proc);
                    count += 1;
                }
            }
            self.rows = try row_list.toOwnedSlice();
            self.procs = result_procs;
        }
    }
};
