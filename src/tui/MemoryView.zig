const std = @import("std");
const plunder = @import("plunder");
const tui = @import("zigtui");
const errorView = @import("ErrorView.zig");
const utils = @import("CommonUtils.zig");
const searchBar = @import("SearchBar.zig");

/// Errors related to Memory view and subviews.
pub const Errors = error{
    no_process_id,
    empty_region_name,
    mismatched_memory,
    incomplete_write,
};

/// Navigation options for cursor movement
pub const Navigation = enum {
    up,
    down,
    left,
    right,
};

/// Structure to handle rendering the Memory within a region
pub const RegionMemoryView = struct {
    /// main theme
    theme: tui.Theme = tui.themes.dracula,
    /// Scroll offset
    scroll_offset: usize = 0,
    /// Currently loaded memory structure.
    memory: ?plunder.mem.Memory = null,
    /// Position of the cursor.
    position: utils.Position = .{},
    /// Structure to manage selection region.
    selection: ?utils.Selection = null,

    /// Get the editable memory copy of this region memory.
    pub fn get_editable_memory(self: *RegionMemoryView, alloc: std.mem.Allocator) !?plunder.mem.MutableMemory {
        if (self.memory) |memory| {
            if (memory.info.is_write()) {
                if (self.selection) |selection| {
                    var start = selection.start;
                    var end = selection.end;
                    if (end < start) {
                        start = selection.end;
                        end = selection.start;
                    }
                    // range is exclusive so we add 1
                    end += 1;
                    return try memory.to_mutable_range(alloc, start, end);
                }
            } else {
                if (errorView.get_error_view()) |error_view| {
                    try error_view.add("Memory is not writable.\n");
                } else |err| {
                    std.log.err("Error: {any}\n", .{err});
                }
            }
        }
        return null;
    }

    /// Search for a given search term and set the selection around it.
    fn search_and_set(self: *RegionMemoryView, buf: []const u8, search_term: []const u8, offset: usize) bool {
        const pos_op = std.mem.indexOfPos(u8, buf, offset, search_term);
        if (pos_op) |pos| {
            const selection: utils.Selection = .{
                .start = pos,
                .end = (pos + search_term.len) - 1,
            };
            self.selection = selection;
            const new_row: usize = @intFromFloat(@ceil(@as(f64, @floatFromInt(selection.end)) / 16.0));
            self.position.row = new_row;
            var row_index: usize = (new_row * 16);
            if (selection.end < row_index) {
                row_index = ((new_row - 1) * 16);
            }
            const new_col: usize = selection.end - row_index;
            self.position.col = new_col;
            return true;
        }
        return false;
    }

    /// Search for the given term.
    pub fn search(self: *RegionMemoryView, search_term: []const u8) bool {
        if (self.memory) |memory| {
            if (memory.buffer) |buf| {
                var offset: usize = 0;
                if (self.selection) |selection| {
                    offset = selection.end;
                }
                if (!self.search_and_set(buf, search_term, offset)) {
                    if (offset != 0) {
                        // search from beginning.
                        return self.search_and_set(buf, search_term, 0);
                    }
                    return false;
                }
                return true;
            }
        }
        return false;
    }

    /// Write a mutable memory to the loaded memory.
    pub fn write(self: *RegionMemoryView, mem: plunder.mem.MutableMemory) !void {
        if (self.memory) |*memory| {
            if (mem.info.start_addr != memory.info.start_addr) {
                return Errors.mismatched_memory;
            }
            if (mem.buffer) |mut_buf| {
                const written = try memory.*.write(mem.starting_offset, mut_buf);
                if (written != mut_buf.len) {
                    return Errors.incomplete_write;
                }
            }
        }
    }

    /// Load a new memory to render.
    pub fn load(self: *RegionMemoryView, memory: plunder.mem.Memory) void {
        // we do not deinitialize memory because we don't own it.
        self.memory = memory;
        self.scroll_offset = 0;
        self.position.row = 0;
        self.position.col = 0;
    }

    /// Toggle the visual selection mode.
    pub fn toggle_selection(self: *RegionMemoryView) void {
        if (self.memory) |memory| {
            if (memory.buffer != null) {
                if (self.selection == null) {
                    const starting_position = self.position_to_index();
                    self.selection = .{
                        .start = starting_position,
                        .end = starting_position,
                    };
                } else {
                    self.selection = null;
                }
            }
        }
    }

    /// Up cursor movement
    fn up(self: *RegionMemoryView, buf: []const u8) void {
        if (self.position.row == 0) {
            const line_idx = buf.len / 16;
            self.position.row = line_idx - 1;
        } else {
            self.position.row -= 1;
        }
    }

    /// Down cursor movement
    fn down(self: *RegionMemoryView, buf: []const u8) void {
        self.position.row += 1;
        self.position.row = self.position.row % (buf.len / 16);
    }

    /// Cursor navigation
    pub fn nav(self: *RegionMemoryView, dir: Navigation) void {
        if (self.memory) |memory| {
            if (memory.buffer) |buf| {
                switch (dir) {
                    .up => {
                        self.up(buf);
                    },
                    .down => {
                        self.down(buf);
                    },
                    .left => {
                        if (self.position.col == 0) {
                            self.position.col = 15;
                            self.up(buf);
                        } else {
                            self.position.col -= 1;
                        }
                    },
                    .right => {
                        if (self.position.col == 15) {
                            self.position.col = 0;
                            self.down(buf);
                        } else {
                            self.position.col += 1;
                        }
                    },
                }
                // if in selection mode update the end position
                if (self.selection) |*selection| {
                    selection.*.end = self.position_to_index();
                }
            }
        }
    }

    /// Unload the current memory.
    pub fn unload(self: *RegionMemoryView) void {
        self.memory = null;
        self.selection = null;
    }
    /// Get the line length for display.
    fn get_line_len(self: *RegionMemoryView) usize {
        if (self.memory) |memory| {
            return memory.buffer.?.len / 16;
        }
        return 0;
    }

    /// Get the index into the memory buffer from the cursor position.
    fn position_to_index(self: *RegionMemoryView) usize {
        if (self.memory == null) return 0;
        return self.position.to_index();
    }

    /// Check if the given index is in the selection range.
    fn is_selected(self: *RegionMemoryView, idx: usize) bool {
        if (self.selection) |selection| {
            var beg = selection.start;
            var end = selection.end;
            if (end < beg) {
                beg = selection.end;
                end = selection.start;
            }
            return idx >= beg and idx <= end;
        } else {
            const position_idx = self.position_to_index();
            return idx == position_idx;
        }
        return false;
    }

    /// Render functions for memory
    pub fn render(self: *RegionMemoryView, arena: std.mem.Allocator, area: tui.Rect, buf: *tui.render.Buffer) !void {
        if (self.memory) |memory| {
            var buffer: []const u8 = undefined;
            if (memory.buffer == null) return;
            buffer = memory.buffer.?;
            const height = area.y + area.height;
            const highlight_selection: tui.Style = .{
                .fg = .dark_gray,
                .bg = self.theme.secondary,
            };
            // minus 4 to account for the different level of offsets.
            // should have a better way of handling this
            const offset_height = height - 4;
            self.scroll_offset = utils.calculate_scroll_offset(
                self.scroll_offset,
                self.position.row,
                offset_height,
            );
            var offset_area = area;
            offset_area.y += 1;
            var idx: usize = self.scroll_offset * 16;
            while (offset_area.y < height) : (offset_area.y += 1) {
                var working_offset = offset_area;
                const cap_width = working_offset.x + working_offset.width;
                const base_addr: usize = memory.info.start_addr + memory.starting_offset + idx;
                const base_addr_str = try std.fmt.allocPrint(
                    arena,
                    "{X:0>12}: ",
                    .{base_addr},
                );
                buf.setString(
                    working_offset.x,
                    working_offset.y,
                    base_addr_str,
                    self.theme.titleStyle(),
                );
                working_offset.x += @intCast(base_addr_str.len);

                // the hex values
                var byte_idx: usize = 0;
                while (byte_idx < 16) : (byte_idx += 1) {
                    const buffer_idx = idx + byte_idx;
                    if (buffer_idx < buffer.len) {
                        const byte_str = try std.fmt.allocPrint(
                            arena,
                            "{X:0>2} ",
                            .{buffer[buffer_idx]},
                        );
                        if (self.is_selected(buffer_idx)) {
                            buf.setString(
                                working_offset.x,
                                working_offset.y,
                                byte_str,
                                highlight_selection,
                            );
                        } else {
                            buf.setString(
                                working_offset.x,
                                working_offset.y,
                                byte_str,
                                self.theme.textStyle(),
                            );
                        }
                        working_offset.x += @intCast(byte_str.len);
                    } else {
                        buf.setString(
                            working_offset.x,
                            working_offset.y,
                            "   ",
                            self.theme.textStyle(),
                        );
                        working_offset.x += 3;
                    }
                }
                buf.setChar(
                    working_offset.x,
                    working_offset.y,
                    '|',
                    self.theme.textStyle(),
                );
                working_offset.x += 1;

                // The character values
                byte_idx = 0;
                while (byte_idx < 16 and working_offset.x < cap_width) : (byte_idx += 1) {
                    const buffer_idx = idx + byte_idx;
                    if (buffer_idx < buffer.len) {
                        const local_char = buffer[buffer_idx];
                        var cur_char: u8 = '.';
                        if (utils.is_printable(local_char)) {
                            cur_char = buffer[buffer_idx];
                        }
                        if (self.is_selected(buffer_idx)) {
                            buf.setChar(
                                working_offset.x,
                                working_offset.y,
                                cur_char,
                                highlight_selection,
                            );
                        } else {
                            buf.setChar(
                                working_offset.x,
                                working_offset.y,
                                cur_char,
                                self.theme.textStyle(),
                            );
                        }
                        working_offset.x += 1;
                    } else {
                        buf.setChar(
                            working_offset.x,
                            working_offset.y,
                            ' ',
                            self.theme.textStyle(),
                        );
                        working_offset.x += 1;
                    }
                }
                if (working_offset.x < cap_width) {
                    buf.setChar(
                        working_offset.x,
                        working_offset.y,
                        '|',
                        self.theme.textStyle(),
                    );
                }

                idx += 16;
            }
        }
    }

    /// Is memory view currently loaded with a memory.
    pub fn is_loaded(self: *RegionMemoryView) bool {
        return self.memory != null;
    }
};

/// Structure for displaying the list of memory blocks for a Region (if there
/// are multiple)
pub const RegionView = struct {
    /// main theme
    theme: tui.Theme = tui.themes.dracula,
    /// currently selected line
    selected: usize = 0,
    /// scroll offset
    scroll_offset: usize = 0,
    /// Currently loaded Region.
    region: ?plunder.mem.Region = null,
    /// The region memory view.
    region_memory_view: RegionMemoryView = .{},

    /// Get the line length of the list of memory blocks for a region.
    fn get_region_line_len(self: *RegionView) usize {
        if (self.region) |region| {
            return region.memory.items.len;
        }
        return 0;
    }

    /// Get the name of the process for the currently selected Region.
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

    /// cleanup
    pub fn deinit(self: *RegionView) void {
        if (self.region) |*region| {
            region.*.deinit();
        }
    }

    /// Select action.
    pub fn select(self: *RegionView) void {
        if (self.region) |region| {
            if (self.region_memory_view.is_loaded()) {} else {
                self.region_memory_view.load(region.memory.items[self.selected]);
            }
        }
    }

    /// Next selection action
    pub fn next_selection(self: *RegionView) void {
        if (!self.region_memory_view.is_loaded()) {
            if (self.region != null) {
                self.selected += 1;
                self.selected = self.selected % self.get_region_line_len();
            }
        }
    }
    /// Previous selection action
    pub fn prev_selection(self: *RegionView) void {
        if (!self.region_memory_view.is_loaded()) {
            if (self.region != null) {
                if (self.selected == 0) {
                    self.selected = self.get_region_line_len() - 1;
                } else {
                    self.selected -= 1;
                }
            }
        }
    }
    /// Load a Region to view.
    pub fn load(self: *RegionView, region: plunder.mem.Region) void {
        if (self.region) |*selected_region| {
            // needs to be deinitialized because we own it.
            selected_region.*.deinit();
        }
        self.region = region;
        self.selected = 0;
        self.scroll_offset = 0;
        if (self.region) |local_region| {
            // if there is only one memory block, automatically jump into it.
            if (local_region.memory.items.len == 1) {
                self.region_memory_view.load(local_region.memory.items[0]);
            }
        }
    }
    /// Unload the current region.
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
    /// Is the region view currently loaded.
    pub fn is_loaded(self: *RegionView) bool {
        return self.region != null;
    }

    /// Main render function for the region view.
    pub fn render(self: *RegionView, arena: std.mem.Allocator, area: tui.Rect, buf: *tui.render.Buffer) !void {
        if (self.region) |selected_region| {
            // show process name.
            buf.setString(
                area.x,
                area.y,
                self.get_selected_name(),
                self.theme.secondaryStyle(),
            );
            // check if memory is loaded currently
            if (self.region_memory_view.is_loaded()) {
                // if loaded only load subview
                try self.region_memory_view.render(arena, area, buf);
                return;
            }
            const height = area.y + area.height;
            // minus 4 for appropriate offset.
            // should be a better way to get this
            const offset_height = height - 4;
            // handle scroll offset
            self.scroll_offset = utils.calculate_scroll_offset(
                self.scroll_offset,
                self.selected,
                offset_height,
            );
            var offset_area = area;
            offset_area.y += 1;
            if (selected_region.memory.items.len > 1) {
                // build and show list of memory blocks and their permissions for a given region.
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

    /// Generate permission string for a given memory.
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

/// Memory table view
pub const MemoryTable = struct {
    /// main theme
    theme: tui.Theme = tui.themes.dracula,
    /// currently selected line.
    selected: usize = 0,
    /// Scroll offset
    scroll_offset: usize = 0,
    /// The region subview.
    region_view: RegionView = .{},
    /// List of region names
    region_names: ?plunder.common.StringListManager = null,

    /// Load the given list of region names.
    pub fn load(self: *MemoryTable, list: plunder.common.StringListManager) void {
        if (self.region_names) |*local_list| {
            local_list.*.deinit();
        }
        self.region_names = list;
    }

    /// Unload region table.
    pub fn unload(self: *MemoryTable) void {
        if (self.region_names) |*local_list| {
            self.region_view.unload();
            local_list.*.deinit();
            self.region_names = null;
        }
    }

    /// Check if this view is the current view.
    pub fn is_viewing(self: *MemoryTable) bool {
        return self.region_names != null and !self.region_view.is_loaded();
    }

    /// Next selection action.
    pub fn next_selection(self: *MemoryTable) void {
        if (self.region_view.is_loaded()) {
            self.region_view.next_selection();
        } else {
            if (self.region_names) |names| {
                self.selected += 1;
                self.selected = self.selected % names.list.items.len;
            }
        }
    }

    /// Previous selection action.
    pub fn prev_selection(self: *MemoryTable) void {
        if (self.region_view.is_loaded()) {
            self.region_view.prev_selection();
        } else {
            if (self.region_names) |names| {
                if (self.selected == 0) {
                    self.selected = names.list.items.len - 1;
                } else {
                    self.selected -= 1;
                }
            }
        }
    }

    /// Deselect action.
    pub fn deselect(self: *MemoryTable) void {
        self.region_view.unload();
    }

    /// Select action.
    pub fn select(self: *MemoryTable, plun: *plunder.Plunder) !void {
        if (self.region_view.is_loaded()) {
            self.region_view.select();
        } else {
            const region_name = self.get_selected_name();
            if (region_name.len > 0) {
                const selected_region = plun.get_region_data(region_name) catch |err| {
                    // certain memory regions like "vsyscall" are legacy emulation regions
                    // and we are not allowed to read from them
                    if (err == error.InputOutput) {
                        const errView = try errorView.get_error_view();
                        try errView.add("Error Input/Output:\nMemory region is not readable.\n");
                        return;
                    }
                    return err;
                };
                if (selected_region) |region| {
                    self.region_view.load(region);
                }
            } else {
                return Errors.empty_region_name;
            }
        }
    }

    /// Render method for memory table
    pub fn render(self: *MemoryTable, arena: std.mem.Allocator, area: tui.Rect, buf: *tui.render.Buffer) !void {
        // check if region view is loaded
        if (self.region_view.is_loaded()) {
            try self.region_view.render(arena, area, buf);
            return;
        }
        // if region view is not loaded we need to display the region names list
        if (self.region_names) |list| {
            const cols: []const tui.widgets.Column = &.{
                tui.widgets.Column{
                    .header = "Region Name",
                },
            };
            // generate rows
            const rows = try self.gen_rows(arena, list);

            const offset_height = area.height - 2;
            self.scroll_offset = utils.calculate_scroll_offset(
                self.scroll_offset,
                self.selected,
                offset_height,
            );
            const table: tui.widgets.Table = .{
                .header_style = self.theme.tableHeaderStyle(),
                .selected_style = self.theme.selectionStyle(),
                .rows = rows,
                .columns = cols,
                .selected = self.selected,
                .offset = self.scroll_offset,
            };

            table.render(area, buf);
        } else {
            // error message
            const msg: tui.widgets.Paragraph = .{
                .text = "Process does not have a memory mapping file.",
                .style = self.theme.warningStyle(),
            };
            msg.render(area, buf);
        }
    }

    /// Cleanup
    pub fn deinit(self: *MemoryTable) void {
        self.region_view.deinit();
        if (self.region_names) |*list| {
            list.*.deinit();
        }
    }

    /// Get the selected Region's name.
    fn get_selected_name(self: *MemoryTable) []const u8 {
        if (self.region_names) |names| {
            return names.list.items[self.selected];
        }
        return "";
    }

    /// Generate rows for the table
    fn gen_rows(self: *MemoryTable, arena: std.mem.Allocator, list_manager: plunder.common.StringListManager) ![]const tui.widgets.Row {
        var result: []tui.widgets.Row = try arena.alloc(
            tui.widgets.Row,
            list_manager.list.items.len,
        );
        for (list_manager.list.items, 0..) |name, idx| {
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

/// Memory view
pub const MemoryView = struct {
    /// main allocator
    alloc: std.mem.Allocator,
    /// arena allocator
    arena: std.heap.ArenaAllocator,
    /// Plunder structure.
    plun: plunder.Plunder,
    /// Memory table subview
    table: MemoryTable = .{},
    /// main theme
    theme: tui.Theme = tui.themes.dracula,
    /// focus flag (controlled by parent)
    focused: bool = false,
    /// The currently loaded process.
    proc: ?plunder.proc.ProcInfo = null,

    /// Initialize
    pub fn init(alloc: std.mem.Allocator) MemoryView {
        return .{
            .alloc = alloc,
            .plun = .init(alloc),
            .arena = .init(alloc),
        };
    }

    /// Set the process to view the memory for.
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

    /// Unload memory view.
    pub fn unload(self: *MemoryView) void {
        if (self.proc != null) {
            self.table.unload();
            self.plun.deinit();
            self.plun = .init(self.alloc);
            self.proc = null;
        }
    }

    /// Reload region names table with no filter.
    pub fn reload_table(self: *MemoryView) !void {
        if (self.proc != null) {
            self.table.selected = 0;
            const list_op = try self.plun.get_region_names(self.alloc);
            if (list_op) |list| {
                self.table.load(list);
            }
        } else {
            return Errors.no_process_id;
        }
    }

    /// Apply search on the region table view.
    pub fn region_table_search(self: *MemoryView, search_term: []const u8) bool {
        if (self.table.is_viewing()) {
            if (self.proc != null) {
                self.table.selected = 0;
                const list_op = self.plun.get_region_names_from_search_term(self.alloc, search_term) catch {
                    const error_view: ?*errorView.ErrorView = errorView.get_error_view() catch null;
                    if (error_view) |*view| {
                        view.*.add("Failed to fetch memory regions.\n") catch {
                            return false;
                        };
                        // return true so the last error message is shown first
                        return true;
                    } else {
                        return false;
                    }
                };
                if (list_op) |list| {
                    self.table.load(list);
                    return true;
                }
            }
        }
        return false;
    }

    /// Memory view write
    pub fn memory_write(self: *MemoryView, mem: plunder.mem.MutableMemory) !void {
        if (self.memory_loaded()) {
            try self.table.region_view.region_memory_view.write(mem);
        }
    }

    /// Memory view search
    pub fn memory_search(self: *MemoryView, search_term: []const u8) bool {
        if (self.memory_loaded()) {
            return self.table.region_view.region_memory_view.search(search_term);
        }
        return false;
    }

    /// Check if a memory view is loaded.
    pub fn memory_loaded(self: *MemoryView) bool {
        return self.table.region_view.region_memory_view.is_loaded();
    }

    /// Toggle the memory view visual selection.
    pub fn memory_visual_selection(self: *MemoryView) void {
        if (self.memory_loaded()) {
            self.table.region_view.region_memory_view.toggle_selection();
        }
    }

    /// Toggle the memory view visual selection.
    pub fn get_mutable_memory(self: *MemoryView) !?plunder.mem.MutableMemory {
        if (self.memory_loaded()) {
            return try self.table.region_view.region_memory_view.get_editable_memory(self.alloc);
        }
        return null;
    }

    /// Up selection action.
    pub fn up_selection(self: *MemoryView) void {
        if (self.memory_loaded()) {
            self.table.region_view.region_memory_view.nav(.up);
        } else {
            self.table.prev_selection();
        }
    }
    /// Down selection action.
    pub fn down_selection(self: *MemoryView) void {
        if (self.memory_loaded()) {
            self.table.region_view.region_memory_view.nav(.down);
        } else {
            self.table.next_selection();
        }
    }

    /// Next Selection action
    pub fn next_selection(self: *MemoryView) void {
        if (self.memory_loaded()) {
            self.table.region_view.region_memory_view.nav(.right);
        }
    }
    /// Previous Selection action
    pub fn prev_selection(self: *MemoryView) void {
        if (self.memory_loaded()) {
            self.table.region_view.region_memory_view.nav(.left);
        }
    }
    /// Deselect action
    pub fn deselect(self: *MemoryView) void {
        self.table.deselect();
    }
    /// Select action
    pub fn select(self: *MemoryView) !void {
        try self.table.select(&self.plun);
    }

    /// Memory view render method
    pub fn render(self: *MemoryView, area: tui.Rect, buf: *tui.render.Buffer) !void {
        const arena = self.arena.allocator();
        // reset arena but retain capacity because we probably are rendering
        // the same amount of things each time
        _ = self.arena.reset(.retain_capacity);
        // conditional title
        var title: []const u8 = " Memory View - [i] toggle Info view; [/] filter; [c] clear filter ";
        if (self.memory_loaded()) {
            title = " Memory View - [i] toggle Info view; [b] back; [v] visual select ";
        } else if (self.table.region_view.is_loaded()) {
            title = " Memory View - [i] toggle Info view; [b] back ";
        }
        const block: tui.widgets.Block = .{
            .style = self.theme.baseStyle(),
            .borders = tui.widgets.Borders.all(),
            .border_symbols = tui.widgets.BorderSymbols.double(),
            .border_style = if (self.focused) self.theme.borderFocusedStyle() else self.theme.borderStyle(),
            .title = title,
        };

        block.render(area, buf);

        const inner_block = block.inner(area);
        if (self.proc != null) {
            // render table subview
            try self.table.render(arena, inner_block, buf);
        } else {
            // if process isn't loaded, render instruction message.
            const msg: tui.widgets.Paragraph = .{
                .text = "Press <ENTER> on a process to view it's memory table.",
                .style = self.theme.infoStyle(),
            };
            msg.render(inner_block, buf);
        }
    }

    /// cleanup
    pub fn deinit(self: *MemoryView) void {
        self.table.deinit();
        self.plun.deinit();
        self.arena.deinit();
    }
};
