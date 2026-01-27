const std = @import("std");
const plunder = @import("plunder");
const tui = @import("zigtui");

pub const Errors = error {
    no_process_id,
};

pub const MemoryTable = struct {
    theme: tui.Theme = tui.themes.dracula,
    selected: usize = 0,

    pub fn render(self: *MemoryTable, arena: std.mem.Allocator, area: tui.Rect, buf: *tui.render.Buffer, list: plunder.common.StringList) !void {
        const cols: []const tui.widgets.Column = &.{
            tui.widgets.Column{
                .header = "Name",
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
    }

    fn gen_rows(_: *MemoryTable, arena: std.mem.Allocator, list: plunder.common.StringList) ![]const tui.widgets.Row {
        var result: []tui.widgets.Row = try arena.alloc(
            tui.widgets.Row,
            list.items.len,
        );
        for (list.items, 0..) |name, idx| {
            const cells = try arena.alloc([]const u8, 1);
            cells[0] = try arena.dupe(u8, name);
            result[idx].cells = cells;
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
        self.proc = proc;
        if (proc.pid) |pid| {
            try self.plun.load(pid);
        } else {
            return Errors.no_process_id;
        }
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
            const list = try self.plun.get_region_names(arena);
            if (list) |mem_list| {
                try self.table.render(arena, inner_block, buf, mem_list);
            } else {
                const msg: tui.widgets.Paragraph = .{
                    .text = "Process does not have a memory mapping file.",
                    .style = self.theme.warningStyle(),
                };
                msg.render(inner_block, buf);
            }
        } else {
            const msg: tui.widgets.Paragraph = .{
                .text = "Press <ENTER> on a process to view it's memory table.",
                .style = self.theme.infoStyle(),
            };
            msg.render(inner_block, buf);
        }
    }
};
