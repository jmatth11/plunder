const std = @import("std");
const plunder = @import("plunder");
const tui = @import("zigtui");

pub const Errors = error{
    no_process_id,
    empty_region_name,
};

pub const RegionMemoryView = struct {
    theme: tui.Theme = tui.themes.dracula,
    selected: usize = 0,
    scroll_offset: usize = 0,
    memory: ?plunder.mem.Memory = null,

    pub fn load(self: *RegionMemoryView, memory: plunder.mem.Memory) void {
        // TODO check if we need to free memory or if we should let the owner free.
        self.memory = memory;
        self.selected = 0;
        self.scroll_offset = 0;
    }

    pub fn unload(self: *RegionMemoryView) void {
        self.memory = null;
    }
    fn get_region_line_len(self: *RegionMemoryView) usize {
        if (self.memory) |memory| {
            return memory.buffer.?.len / 16;
        }
        return 0;
    }
    pub fn next_selection(self: *RegionMemoryView) void {
        if (self.memory != null) {
            self.selected += 1;
            self.selected = self.selected % self.get_region_line_len();
        }
    }
    pub fn prev_selection(self: *RegionMemoryView) void {
        if (self.memory != null) {
            if (self.selected == 0) {
                self.selected = self.get_region_line_len() - 1;
            } else {
                self.selected -= 1;
            }
        }
    }
    pub fn render(self: *RegionMemoryView, arena: std.mem.Allocator, area: tui.Rect, buf: *tui.render.Buffer) !void {
        if (self.memory) |memory| {
            const height = area.y + area.height;
            // minus 4 for appropriate offset.
            // this number feels like magic, not sure why it's 4
            const offset_height = height - 4;
            const scroll_offset_height = self.scroll_offset + offset_height;
            if (self.selected > scroll_offset_height) {
                self.scroll_offset = self.selected - offset_height;
            } else if (self.selected < self.scroll_offset) {
                self.scroll_offset = self.selected;
            }
            var offset_area = area;
            offset_area.y += 1;
            var idx: usize = self.scroll_offset;
            while (offset_area.y < height) : (offset_area.y += 1) {
                const line_op = try memory.hex_dump_line(arena, idx);
                if (line_op) |line| {
                    if (self.selected == idx) {
                        buf.setString(
                            offset_area.x,
                            offset_area.y,
                            line,
                            self.theme.highlightStyle(),
                        );
                    } else {
                        buf.setString(
                            offset_area.x,
                            offset_area.y,
                            line,
                            self.theme.primaryStyle(),
                        );
                    }
                }
                idx += 1;
            }
        }
        // TODO maybe think of "edit" mode to mimic model view controller style
    }
    pub fn is_loaded(self: *RegionMemoryView) bool {
        return self.memory != null;
    }
};

pub const RegionView = struct {
    theme: tui.Theme = tui.themes.dracula,
    selected: usize = 0,
    scroll_offset: usize = 0,
    region: ?plunder.mem.Region = null,
    region_memory_view: RegionMemoryView = .{},

    fn get_region_line_len(self: *RegionView) usize {
        if (self.region) |region| {
            const count = region.memory.items.len;
            if (count == 1) {
                const memory = region.memory.items[0];
                return memory.buffer.?.len / 16;
            }
            return count;
        }
        return 0;
    }

    fn get_selected_name(self: *RegionView) []const u8 {
        if (self.region) |region| {
            if (region.memory.items.len > 0) {
                const memory = region.memory.items[0];
                if (memory.info.pathname) |pathname| {
                    return pathname;
                } else {
                    return "undefined";
                }
            }
        }
        return "";
    }

    pub fn select(self: *RegionView) void {
        if (self.region) |region| {
            if (self.region_memory_view.is_loaded()) {

            } else {
                self.region_memory_view.load(region.memory.items[self.selected]);
            }
        }
    }

    pub fn next_selection(self: *RegionView) void {
        if (self.region_memory_view.is_loaded()) {
            self.region_memory_view.next_selection();
        } else {
            if (self.region != null) {
                self.selected += 1;
                self.selected = self.selected % self.get_region_line_len();
            }
        }
    }
    pub fn prev_selection(self: *RegionView) void {
        if (self.region_memory_view.is_loaded()) {
            self.region_memory_view.prev_selection();
        } else {
            if (self.region != null) {
                if (self.selected == 0) {
                    self.selected = self.get_region_line_len() - 1;
                } else {
                    self.selected -= 1;
                }
            }
        }
    }
    pub fn load(self: *RegionView, region: plunder.mem.Region) void {
        if (self.region) |*selected_region| {
            selected_region.*.deinit();
        }
        self.region = region;
        self.selected = 0;
        self.scroll_offset = 0;
        if (self.region) |local_region| {
            if (local_region.memory.items.len == 1) {
                self.region_memory_view.load(local_region.memory.items[0]);
            }
        }
    }
    pub fn unload(self: *RegionView) void {
        if (self.region) |*selected_region| {
            if (self.region_memory_view.is_loaded()) {
                self.region_memory_view.unload();
                // if there was only one memory region we back all the way out.
                // so if there are multiple we go back to the region memory list.
                if (selected_region.memory.items.len != 1) {
                    return;
                }
            }
            selected_region.*.deinit();
            self.region = null;
        }
    }
    pub fn is_loaded(self: *RegionView) bool {
        return self.region != null;
    }

    pub fn render(self: *RegionView, arena: std.mem.Allocator, area: tui.Rect, buf: *tui.render.Buffer) !void {
        if (self.region) |selected_region| {
            buf.setString(
                area.x,
                area.y,
                self.get_selected_name(),
                self.theme.secondaryStyle(),
            );
            // check if memory is loaded currently
            if (self.region_memory_view.is_loaded()) {
                try self.region_memory_view.render(arena, area, buf);
                return;
            }
            const height = area.y + area.height;
            // minus 4 for appropriate offset.
            // this number feels like magic, not sure why it's 4
            const offset_height = height - 4;
            const scroll_offset_height = self.scroll_offset + offset_height;
            if (self.selected > scroll_offset_height) {
                self.scroll_offset = self.selected - offset_height;
            } else if (self.selected < self.scroll_offset) {
                self.scroll_offset = self.selected;
            }
            var offset_area = area;
            offset_area.y += 1;
            if (selected_region.memory.items.len > 1) {
                for (selected_region.memory.items, 0..) |memory, idx| {
                    if (offset_area.y >= height) {
                        break;
                    }
                    const starting_offset = memory.info.start_addr + memory.starting_offset;
                    var line: []const u8 = "";
                    const perm_str = try self.gen_permission_str(arena, memory);
                    if (self.selected == idx) {
                        line = try std.fmt.allocPrint(
                            arena,
                            "> {X:0>12}-{X:0>12} {s}",
                            .{
                                starting_offset,
                                starting_offset + memory.buffer.?.len,
                                perm_str,
                            },
                        );
                    } else {
                        line = try std.fmt.allocPrint(
                            arena,
                            "  {X:0>12}-{X:0>12} {s}",
                            .{
                                starting_offset,
                                starting_offset + memory.buffer.?.len,
                                perm_str,
                            },
                        );
                    }
                    buf.setString(
                        offset_area.x,
                        offset_area.y,
                        line,
                        self.theme.primaryStyle(),
                    );
                    offset_area.y += 1;
                }
            }
        }
    }

    fn gen_permission_str(_: *RegionView, arena: std.mem.Allocator, memory: plunder.mem.Memory) ![]const u8 {
        var rd: u8 = '-';
        if (memory.info.is_read()) {
            rd = 'r';
        }
        var wr: u8 = '-';
        if (memory.info.is_write()) {
            wr = 'w';
        }
        var ex: u8 = '-';
        if (memory.info.is_execute()) {
            ex = 'x';
        }
        var sh: u8 = 'p';
        if (memory.info.is_shared()) {
            sh = 's';
        }
        return try std.fmt.allocPrint(arena, "{c}{c}{c}{c}", .{ rd, wr, ex, sh });
    }
};

pub const MemoryTable = struct {
    theme: tui.Theme = tui.themes.dracula,
    selected: usize = 0,
    region_view: RegionView = .{},
    list: ?plunder.common.StringList = null,

    pub fn load(self: *MemoryTable, list: plunder.common.StringList) void {
        if (self.list) |local_list| {
            local_list.deinit();
        }
        self.list = list;
    }

    pub fn next_selection(self: *MemoryTable) void {
        if (self.region_view.is_loaded()) {
            self.region_view.next_selection();
        } else {
            if (self.list) |list| {
                self.selected += 1;
                self.selected = self.selected % list.items.len;
            }
        }
    }

    pub fn prev_selection(self: *MemoryTable) void {
        if (self.region_view.is_loaded()) {
            self.region_view.prev_selection();
        } else {
            if (self.list) |list| {
                if (self.selected == 0) {
                    self.selected = list.items.len - 1;
                } else {
                    self.selected -= 1;
                }
            }
        }
    }

    pub fn deselect(self: *MemoryTable) void {
        self.region_view.unload();
    }

    pub fn select(self: *MemoryTable, plun: *plunder.Plunder) !void {
        if (self.region_view.is_loaded()) {
            self.region_view.select();
        } else {
            const region_name = self.get_selected_name();
            if (region_name.len > 0) {
                const selected_region = try plun.get_region_data(region_name);
                if (selected_region) |region| {
                    self.region_view.load(region);
                }
            } else {
                return Errors.empty_region_name;
            }
        }
    }

    pub fn render(self: *MemoryTable, arena: std.mem.Allocator, area: tui.Rect, buf: *tui.render.Buffer) !void {
        if (self.region_view.is_loaded()) {
            try self.region_view.render(arena, area, buf);
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
    pub fn deselect(self: *MemoryView) void {
        self.table.deselect();
    }
    pub fn select(self: *MemoryView) !void {
        try self.table.select(&self.plun);
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
