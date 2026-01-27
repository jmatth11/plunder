const std = @import("std");
const plunder = @import("plunder");
const tui = @import("zigtui");

pub const Errors = error{
    uninitialized_procs,
};

pub const ProcView = struct {
    alloc: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    procs: ?plunder.proc.ProcList = null,
    theme: tui.Theme = tui.themes.dracula,
    rows: ?[]tui.widgets.Row = null,
    cols: []const tui.widgets.Column,
    selected: usize = 0,
    focused: bool = true,

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

    pub fn render(self: *ProcView, area: tui.Rect, buf: *tui.render.Buffer) !void {
        const block: tui.widgets.Block = .{
            .style = self.theme.baseStyle(),
            .borders = tui.widgets.Borders.all(),
            .border_symbols = tui.widgets.BorderSymbols.double(),
            .border_style = if (self.focused) self.theme.borderFocusedStyle() else self.theme.borderStyle(),
            .title = "Process List",
        };

        block.render(area, buf);

        try self.gen_rows();

        const inner_block = block.inner(area);
        const offset_height = inner_block.height - 2;
        const offset = if (self.selected >= offset_height) self.selected - offset_height else 0;

        // TODO see if we can increase the Command column size to fill up the remaining width
        const table: tui.widgets.Table = .{
            .columns = self.cols,
            .header_style = self.theme.tableHeaderStyle(),
            .rows = self.rows.?,
            .selected_style = self.theme.selectionStyle(),
            .selected = self.selected,
            .offset = offset,
        };

        table.render(inner_block, buf);
    }

    pub fn get_selected(self: *ProcView) Errors!plunder.proc.ProcInfo {
        if (self.procs) |procs| {
            return procs.procs.items[self.selected];
        }
        return Errors.uninitialized_procs;
    }

    pub fn next_selection(self: *ProcView) void {
        if (self.rows) |rows| {
            self.selected += 1;
            self.selected = self.selected % rows.len;
        }
    }
    pub fn prev_selection(self: *ProcView) void {
        if (self.rows) |rows| {
            if (self.selected == 0) {
                self.selected = rows.len - 1;
            } else {
                self.selected -= 1;
            }
        }
    }

    pub fn deinit(self: *ProcView) void {
        self.arena.deinit();
        if (self.rows) |rows| {
            self.alloc.free(rows);
            self.rows = null;
        }
    }

    fn gen_rows(self: *ProcView) !void {
        if (self.rows == null) {
            // TODO not sure if I like this
            if (self.procs == null) {
                self.procs = try plunder.proc.get_processes(self.alloc);
            }

            if (self.procs) |procs_list| {
                self.rows = try self.alloc.alloc(
                    tui.widgets.Row,
                    procs_list.procs.items.len,
                );
                for (procs_list.procs.items, 0..) |proc, idx| {
                    const pid_str: []const u8 = try std.fmt.allocPrint(
                        self.arena.allocator(),
                        "{}",
                        .{proc.pid.?},
                    );
                    const command: []const u8 = try self.arena.allocator().dupe(
                        u8,
                        proc.command,
                    );
                    const cells = try self.arena.allocator().alloc([]const u8, 2);
                    cells[0] = pid_str;
                    cells[1] = command;
                    self.rows.?[idx] = tui.widgets.Row{
                        .style = self.theme.tableRowStyle(idx, false),
                        .cells = cells,
                    };
                }
            }
        }
    }
};
