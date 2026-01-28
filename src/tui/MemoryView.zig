const std = @import("std");
const plunder = @import("plunder");
const tui = @import("zigtui");

pub const Errors = error{
    no_process_id,
};

pub const MemoryTable = struct {
    theme: tui.Theme = tui.themes.dracula,
    selected: usize = 0,
    selected_region: ?plunder.mem.Region = null,
    list: ?plunder.common.StringList = null,

    pub fn load(self: *MemoryTable, list: plunder.common.StringList) void {
        if (self.list) |local_list| {
            local_list.deinit();
        }
        self.list = list;
    }

    pub fn next_selection(self: *MemoryTable) void {
        if (self.list) |list| {
            self.selected += 1;
            self.selected = self.selected % list.items.len;
        }
    }

    pub fn prev_selection(self: *MemoryTable) void {
        if (self.list) |list| {
            if (self.selected == 0) {
                self.selected = list.items.len - 1;
            } else {
                self.selected -= 1;
            }
        }
    }

    pub fn render(self: *MemoryTable, arena: std.mem.Allocator, area: tui.Rect, buf: *tui.render.Buffer) !void {
        if (self.selected_region) |selected_region| {
            buf.setString(area.x, area.y, self.get_selected_name(), self.theme.secondaryStyle());
            const height = area.y + area.height;
            var offset_area = area;
            offset_area.y += 1;
            if (selected_region.memory.items.len == 1) {
                const memory = selected_region.memory.items[0];
                var idx:usize = 0;
                while (offset_area.y < height) : (offset_area.y += 1) {
                    const line = try memory.hex_dump_line(arena, idx);
                    buf.setString(offset_area.x, offset_area.y, line, self.theme.primaryStyle());
                    idx += 1;
                }
            } else if (selected_region.memory.items.len > 1) {
                for (selected_region.memory.items) |memory| {
                    if (offset_area.y >= height) {
                        break;
                    }
                    const starting_offset = memory.info.start_addr + memory.starting_offset;
                    const line = std.fmt.allocPrint(
                        arena, "{X:0>12}-{X:0>12}", .{starting_offset, starting_offset + memory.buffer.?.len});
                    buf.setString(offset_area.x, offset_area.y, line, self.theme.primaryStyle());
                    offset_area.y += 1;
                    // TODO add permisions, add function to set selected region.
                    // TODO maybe think of "edit" mode to mimic model view controller style
                }
            }
            return;
        }
        if (self.list) |list| {
            const cols: []const tui.widgets.Column = &.{
                tui.widgets.Column{
                    .header = "Region Name",
                },
            };
            const rows = try self.gen_rows(arena, list);

            const offset_height = area.height - 2;
            const offset = if (self.selected >= offset_height) self.selected - offset_height else 0;
            const table: tui.widgets.Table = .{
                .header_style = self.theme.tableHeaderStyle(),
                .selected_style = self.theme.selectionStyle(),
                .rows = rows,
                .columns = cols,
                .selected = self.selected,
                .offset = offset,
            };

            table.render(area, buf);
        } else {
            const msg: tui.widgets.Paragraph = .{
                .text = "Process does not have a memory mapping file.",
                .style = self.theme.warningStyle(),
            };
            msg.render(area, buf);
        }
    }

    fn get_selected_name(self: *MemoryTable) []const u8 {
        if (self.list) |list| {
            return list.items[self.selected];
        }
        return "";
    }

    fn gen_rows(self: *MemoryTable, arena: std.mem.Allocator, list: plunder.common.StringList) ![]const tui.widgets.Row {
        var result: []tui.widgets.Row = try arena.alloc(
            tui.widgets.Row,
            list.items.len,
        );
        for (list.items, 0..) |name, idx| {
            const cells = try arena.alloc([]const u8, 1);
            cells[0] = try arena.dupe(u8, name);
            const row: tui.widgets.Row = .{
                .cells = cells,
                .style = self.theme.tableRowStyle(idx, idx == self.selected),
            };
            result[idx] = row;
        }
        return result;
    }
};

pub const MemoryView = struct {
    alloc: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    plun: plunder.Plunder,
    table: MemoryTable = .{},
    theme: tui.Theme = tui.themes.dracula,
    focused: bool = false,
    proc: ?plunder.proc.ProcInfo = null,

    pub fn init(alloc: std.mem.Allocator) MemoryView {
        return .{
            .alloc = alloc,
            .plun = .init(alloc),
            .arena = .init(alloc),
        };
    }

    pub fn set_proc(self: *MemoryView, proc: plunder.proc.ProcInfo) !void {
        if (self.proc != null) {
            self.plun.deinit();
            self.plun = .init(self.alloc);
            self.proc.?.deinit();
        }
        self.proc = proc;
        if (proc.pid) |pid| {
            try self.plun.load(pid);
            self.table.selected = 0;
            const list_op = try self.plun.get_region_names(self.alloc);
            if (list_op) |list| {
                self.table.load(list);
            }
        } else {
            return Errors.no_process_id;
        }
    }

    pub fn next_selection(self: *MemoryView) void {
        self.table.next_selection();
    }
    pub fn prev_selection(self: *MemoryView) void {
        self.table.prev_selection();
    }

    pub fn render(self: *MemoryView, area: tui.Rect, buf: *tui.render.Buffer) !void {
        const arena = self.arena.allocator();
        _ = self.arena.reset(.retain_capacity);
        const block: tui.widgets.Block = .{
            .style = self.theme.baseStyle(),
            .borders = tui.widgets.Borders.all(),
            .border_symbols = tui.widgets.BorderSymbols.double(),
            .border_style = if (self.focused) self.theme.borderFocusedStyle() else self.theme.borderStyle(),
            .title = "Memory View",
        };

        block.render(area, buf);

        const inner_block = block.inner(area);
        if (self.proc != null) {
            try self.table.render(arena, inner_block, buf);
        } else {
            const msg: tui.widgets.Paragraph = .{
                .text = "Press <ENTER> on a process to view it's memory table.",
                .style = self.theme.infoStyle(),
            };
            msg.render(inner_block, buf);
        }
    }
};
