const std = @import("std");
const tui = @import("zigtui");
const utils = @import("CommonUtils.zig");
const plunder = @import("plunder");
const memoryView = @import("MemoryView.zig");
const errorView = @import("ErrorView.zig");

const EntryMode = enum {
    text,
    hex,
};

pub const EditMemoryView = struct {
    /// Main allocator
    alloc: std.mem.Allocator,
    /// Arena allocator
    arena: std.heap.ArenaAllocator,
    /// Main theme
    theme: tui.Theme = tui.themes.dracula,
    /// The memory to edit.
    memory: ?plunder.mem.MutableMemory = null,
    /// Text entry mode.
    entry_mode: EntryMode = .hex,
    /// Position of the cursor.
    position: utils.Position = .{},
    /// Scroll offset.
    scroll_offset: usize = 0,
    /// The working buffer.
    working_buffer: [2]u8 = @splat(0),
    /// Working buffer length.
    working_buffer_len: usize = 0,

    /// Initialize
    pub fn init(alloc: std.mem.Allocator) EditMemoryView {
        return .{
            .alloc = alloc,
            .arena = .init(alloc),
        };
    }

    /// Load the mutable memory to use for editing.
    pub fn load(self: *EditMemoryView, new_memory: plunder.mem.MutableMemory) void {
        if (self.memory) |*memory| {
            memory.*.deinit();
        }
        self.memory = new_memory;
        self.position.row = 0;
        self.position.col = 0;
        self.scroll_offset = 0;
        self.load_working_buffer();
    }

    /// Unload the mutable memory.
    pub fn unload(self: *EditMemoryView) void {
        if (self.memory) |*memory| {
            memory.*.deinit();
            self.memory = null;
        }
    }

    /// Up cursor movement
    fn up(self: *EditMemoryView, buf: []const u8) void {
        if (self.position.row == 0) {
            const max_lines: usize = @intFromFloat(@ceil(@as(f64, @floatFromInt(buf.len)) / 16.0));
            self.position.row = max_lines - 1;
        } else {
            self.position.row -= 1;
        }
        const end_col = self.get_end_col_position();
        if (end_col == 0) {
            self.position.col = 0;
        } else if (self.position.col >= end_col) {
            self.position.col = end_col - 1;
        }
    }

    /// Down cursor movement
    fn down(self: *EditMemoryView, buf: []const u8) void {
        self.position.row += 1;
        const max_lines: usize = @intFromFloat(@ceil(@as(f64, @floatFromInt(buf.len)) / 16.0));
        self.position.row = self.position.row % max_lines;
        const end_col = self.get_end_col_position();
        if (end_col == 0) {
            self.position.col = 0;
        } else if (self.position.col >= end_col) {
            self.position.col = end_col - 1;
        }
    }

    /// Load the working buffer with the value under the cursor.
    fn load_working_buffer(self: *EditMemoryView) void {
        if (self.memory) |memory| {
            if (memory.buffer) |buf| {
                const idx = self.position.to_index();
                if (idx < buf.len) {
                    const byte = buf[idx];
                    const hex_str = std.fmt.hex(byte);
                    std.mem.copyForwards(u8, self.working_buffer[0..], hex_str[0..]);
                    self.working_buffer_len = 2;
                }
            }
        }
    }
    /// Write the working buffer content to the mutable memory buffer.
    fn write_working_buffer(self: *EditMemoryView) void {
        if (self.memory) |memory| {
            if (memory.buffer) |buf| {
                const idx = self.position.to_index();
                if (idx < buf.len) {
                    buf[idx] = std.fmt.parseInt(
                        u8,
                        self.get_working_buffer(),
                        16,
                    ) catch 0;
                }
            }
        }
    }

    /// Get the working buffer normalized.
    /// This function will pad zeros if the whole array is not filled.
    fn get_working_buffer(self: *EditMemoryView) []const u8 {
        if (self.working_buffer_len == 0) {
            self.working_buffer[0] = '0';
            self.working_buffer[1] = '0';
            self.working_buffer_len = 2;
            return self.working_buffer[0..];
        }
        if (self.working_buffer_len == 1) {
            self.working_buffer[1] = self.working_buffer[0];
            self.working_buffer[0] = '0';
            self.working_buffer_len = 2;
            return self.working_buffer[0..];
        }
        return self.working_buffer[0..];
    }

    /// Print the working buffer correctly to the screen.
    fn print_working_buffer(self: *EditMemoryView, arena: std.mem.Allocator) ![]const u8 {
        if (self.working_buffer_len == 1) {
            var c = self.working_buffer[0];
            if (std.ascii.isAlphabetic(c)) {
                c = std.ascii.toUpper(c);
            }
            return try std.fmt.allocPrint(arena, "{c}  ", .{c});
        }
        if (self.working_buffer_len == 2) {
            var c = self.working_buffer[0];
            if (std.ascii.isAlphabetic(c)) {
                c = std.ascii.toUpper(c);
            }
            var c2 = self.working_buffer[1];
            if (std.ascii.isAlphabetic(c2)) {
                c2 = std.ascii.toUpper(c2);
            }
            return try std.fmt.allocPrint(arena, "{c}{c} ", .{ c, c2 });
        }
        return try arena.dupe(u8, "   ");
    }

    /// Add character to the working buffer.
    pub fn add_character(self: *EditMemoryView, c: u21) !void {
        var error_view = try errorView.get_error_view();
        switch (self.entry_mode) {
            .hex => {
                if (c < 256) {
                    var local_c: u8 = @intCast(c);
                    if (std.ascii.isHex(local_c)) {
                        // capitalize letters
                        if (std.ascii.isAlphabetic(local_c)) {
                            local_c = std.ascii.toUpper(local_c);
                        }
                        if (self.working_buffer_len < 2) {
                            self.working_buffer[self.working_buffer_len] = local_c;
                            self.working_buffer_len += 1;
                            if (self.working_buffer_len == 2) {
                                self.nav(.right);
                            }
                        }
                    } else {
                        try error_view.add("Must be a hex number: 0-9, A-F.");
                    }
                } else {
                    try error_view.add("Must be a hex number: 0-9, A-F.");
                }
            },
            .text => {
                const max_value = std.math.maxInt(u8);
                if (c <= max_value) {
                    const local_c: u8 = @intCast(c);
                    const hex_str = std.fmt.hex(local_c);
                    std.mem.copyForwards(u8, self.working_buffer[0..], hex_str[0..]);
                    self.nav(.right);
                } else {
                    try error_view.add("Currently unsupported text value. Must be unicode codepoint between 0x0-0xFFFF.");
                }
            },
        }
    }

    /// Delete character from the working buffer.
    pub fn delete_character(self: *EditMemoryView) void {
        var clear: bool = false;
        switch (self.entry_mode) {
            .hex => {
                if (self.working_buffer_len > 0) {
                    self.working_buffer_len -= 1;
                } else {
                    clear = true;
                }
            },
            .text => {
                clear = true;
            },
        }
        if (clear) {
            self.working_buffer[0] = 0;
            self.working_buffer[1] = 0;
            self.working_buffer_len = 2;
            self.nav(.left);
        }
    }

    /// Get the end column position based on the current row position.
    fn get_end_col_position(self: *EditMemoryView) usize {
        if (self.memory) |memory| {
            if (memory.buffer) |buf| {
                const line = self.position.row * 16;
                const ref_buf = buf[line..];
                if (ref_buf.len >= 16) {
                    return 16;
                }
                return ref_buf.len;
            }
        }
        return 0;
    }

    /// Cursor navigation
    pub fn nav(self: *EditMemoryView, dir: memoryView.Navigation) void {
        if (self.memory) |memory| {
            if (memory.buffer) |buf| {
                self.write_working_buffer();
                switch (dir) {
                    .up => {
                        self.up(buf);
                    },
                    .down => {
                        self.down(buf);
                    },
                    .left => {
                        if (self.position.col == 0) {
                            self.up(buf);
                            self.position.col = self.get_end_col_position() - 1;
                        } else {
                            self.position.col -= 1;
                        }
                    },
                    .right => {
                        const end_position = self.get_end_col_position() - 1;
                        if (self.position.col == end_position) {
                            self.position.col = 0;
                            self.down(buf);
                        } else {
                            self.position.col += 1;
                        }
                    },
                }
                self.load_working_buffer();
            }
        }
    }

    /// Toggle the entry mode between text and hex.
    pub fn toggle_entry_mode(self: *EditMemoryView) void {
        self.entry_mode = switch (self.entry_mode) {
            .text => .hex,
            .hex => .text,
        };
    }

    /// Check if the given index is in the selection range.
    fn is_selected(self: *EditMemoryView, idx: usize) bool {
        const position_idx = self.position.to_index();
        return idx == position_idx;
    }

    /// Get the height of the buffer if printed to the screen.
    fn get_height(self: *EditMemoryView) u16 {
        if (self.memory) |memory| {
            if (memory.buffer) |buf| {
                return @intFromFloat(@ceil(@as(f64, @floatFromInt(buf.len)) / 16.0));
            }
        }
        return 0;
    }

    fn get_width(self: *EditMemoryView) !u16 {
        if (self.memory) |memory| {
            const test_str = try std.fmt.allocPrint(
                self.alloc,
                "{X:0>12}: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|",
                .{memory.info.end_addr},
            );
            defer self.alloc.free(test_str);
            return @intCast(test_str.len);
        }
        return 0;
    }

    /// Render edit memory view
    pub fn render(self: *EditMemoryView, area: tui.Rect, buf: *tui.render.Buffer) !void {
        const arena = self.arena.allocator();
        _ = self.arena.reset(.retain_capacity);
        var title: []const u8 = " Memory Editor (HEX Mode) ";
        if (self.entry_mode == .text) {
            title = " Memory Editor (TEXT Mode) ";
        }
        const block: tui.widgets.Block = .{
            .title = title,
            .title_style = self.theme.titleStyle(),
            .borders = .all(),
            .border_symbols = .rounded(),
            .border_style = self.theme.borderFocusedStyle(),
            .style = self.theme.baseStyle(),
        };
        const max_width = try self.get_width();
        var block_area = area;
        if (max_width != 0) {
            block_area.width = max_width + 3;
            block_area.y = @intFromFloat(@as(f32, @floatFromInt(area.height)) * 0.2);
            block_area.height = area.height - (block_area.y * 2);
            const start_x: u16 = @intFromFloat(@as(f32, @floatFromInt(area.width - block_area.width)) / 2.0);
            block_area.x = start_x;
        }
        block.render(block_area, buf);
        var inner_block = block.inner(block_area);
        // clear screen
        buf.fillArea(inner_block, ' ', self.theme.baseStyle());

        // add a little padding
        inner_block.x += 1;
        inner_block.width -= 1;

        buf.setString(
            inner_block.x,
            inner_block.y,
            "[ESC] Cancel; [Enter] Accept; [ARROW KEYS] movement; [TAB] Toggle Entry Mode",
            self.theme.borderFocusedStyle(),
        );
        inner_block.y += 1;

        var instructions: []const u8 = "Instructions: [BACKSPACE] to delete the characters, then type the hex number.";
        if (self.entry_mode == .text) {
            instructions = "Instructions: Type the key you'd like to replace the hex value with.";
        }
        buf.setString(
            inner_block.x,
            inner_block.y,
            instructions,
            self.theme.textStyle(),
        );
        inner_block.y += 1;
        inner_block.height -= 2;

        if (self.memory) |memory| {
            var buffer: []const u8 = undefined;
            if (memory.buffer == null) return;
            buffer = memory.buffer.?;
            const highlight_selection: tui.Style = .{
                .fg = .dark_gray,
                .bg = self.theme.secondary,
            };

            const offset_height = inner_block.height - 2;
            self.scroll_offset = utils.calculate_scroll_offset(
                self.scroll_offset,
                self.position.row,
                offset_height,
            );
            var offset_area = inner_block;
            const height_position = offset_area.y + offset_area.height;
            offset_area.y += 1;
            var idx: usize = self.scroll_offset * 16;
            while (offset_area.y < height_position and idx < buffer.len) : (offset_area.y += 1) {
                var working_offset = offset_area;
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
                        if (self.is_selected(buffer_idx)) {
                            const byte_str = try self.print_working_buffer(arena);
                            buf.setString(
                                working_offset.x,
                                working_offset.y,
                                byte_str,
                                highlight_selection,
                            );
                        } else {
                            const byte_str = try std.fmt.allocPrint(
                                arena,
                                "{X:0>2} ",
                                .{buffer[buffer_idx]},
                            );
                            buf.setString(
                                working_offset.x,
                                working_offset.y,
                                byte_str,
                                self.theme.textStyle(),
                            );
                        }
                        working_offset.x += 3;
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
                while (byte_idx < 16) : (byte_idx += 1) {
                    const buffer_idx = idx + byte_idx;
                    if (buffer_idx < buffer.len) {
                        const local_char = buffer[buffer_idx];
                        var cur_char: u8 = '.';
                        if (utils.is_printable(local_char)) {
                            cur_char = buffer[buffer_idx];
                        }
                        if (self.is_selected(buffer_idx)) {
                            var text_char = cur_char;
                            if (self.working_buffer_len == 2) {
                                var out: [1]u8 = @splat(0);
                                _ = try std.fmt.hexToBytes(&out, self.working_buffer[0..]);
                                if (utils.is_printable(out[0])) {
                                    text_char = out[0];
                                }
                            }
                            buf.setChar(
                                working_offset.x,
                                working_offset.y,
                                text_char,
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
                buf.setChar(
                    working_offset.x,
                    working_offset.y,
                    '|',
                    self.theme.textStyle(),
                );

                idx += 16;
            }
        }
    }

    /// Check if edit memory view is loaded.
    pub fn is_loaded(self: *EditMemoryView) bool {
        return self.memory != null;
    }

    /// Cleanup
    pub fn deinit(self: *EditMemoryView) void {
        self.arena.deinit();
        if (self.memory) |*memory| {
            memory.*.deinit();
        }
    }
};
