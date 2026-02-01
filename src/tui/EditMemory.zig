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
    scroll_offset: usize = 0,
    /// The working buffer.
    working_buffer: [2]u8 = @splat(0),
    working_buffer_len: usize = 0,

    pub fn init(alloc: std.mem.Allocator) EditMemoryView {
        return .{
            .alloc = alloc,
            .arena = .init(alloc),
        };
    }

    pub fn load(self: *EditMemoryView, new_memory: plunder.mem.MutableMemory) void {
        if (self.memory) |*memory| {
            memory.*.deinit();
        }
        self.memory = new_memory;
    }

    pub fn unload(self: *EditMemoryView) void {
        if (self.memory) |*memory| {
            memory.*.deinit();
            self.memory = null;
        }
    }

    /// Up cursor movement
    fn up(self: *EditMemoryView, buf: []const u8) void {
        if (self.position.row == 0) {
            const line_idx = buf.len / 16;
            self.position.row = line_idx - 1;
        } else {
            self.position.row -= 1;
        }
    }

    /// Down cursor movement
    fn down(self: *EditMemoryView, buf: []const u8) void {
        self.position.row += 1;
        self.position.row = self.position.row % (buf.len / 16);
    }

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
    fn write_working_buffer(self: *EditMemoryView) void {
        if (self.memory) |memory| {
            if (memory.buffer) |buf| {
                const idx = self.position.to_index();
                if (idx < buf.len) {
                    buf[idx] = std.fmt.parseInt(
                        u8,
                        self.working_buffer[0..],
                        16,
                    ) catch 0;
                }
            }
        }
    }

    pub fn add_character(self: *EditMemoryView, c: u21) !void {
        var error_view = try errorView.get_error_view();
        switch (self.entry_mode) {
            .hex => {
                if (c < 256) {
                    const local_c: u8 = @intCast(c);
                    if (std.ascii.isHex(local_c)) {
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
                } else {}
            },
            .text => {
                const max_value = std.math.maxInt(u16);
                if (c <= max_value) {
                    const local_c: u16 = @intCast(c);
                    const hex_str = std.fmt.hex(local_c);
                    std.mem.copyForwards(u8, self.working_buffer[0..], hex_str[0..]);
                    self.nav(.right);
                } else {
                    try error_view.add("Currently unsupported text value. Must be unicode codepoint between 0x0-0xFFFF.");
                }
            },
        }
    }

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

    /// Render edit memory view
    pub fn render(self: *EditMemoryView, area: tui.Rect, buf: *tui.render.Buffer) !void {
        const arena = self.arena.allocator();
        _ = self.arena.reset(.retain_capacity);
        const height = area.height;
        var title: []const u8 = " Memory Editor (HEX Mode) ";
        if (self.entry_mode == .text) {
            title = " Memory Editor (TEXT Mode) ";
        }
        const block: tui.widgets.Block = .{
            .title = title,
            .title_style = self.theme.titleStyle(),
            .borders = .all(),
            .border_symbols = .rounded(),
            .border_style = self.theme.borderStyle(),
            .style = self.theme.baseStyle(),
        };
        block.render(area, buf);
        const inner_block = block.inner(area);
        buf.fillArea(inner_block, ' ', self.theme.baseStyle());
        if (self.memory) |memory| {
            var buffer: []const u8 = undefined;
            if (memory.buffer == null) return;
            buffer = memory.buffer.?;
            const highlight_selection: tui.Style = .{
                .fg = .dark_gray,
                .bg = self.theme.secondary,
            };

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
                while (byte_idx < 16) : (byte_idx += 1) {
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

    pub fn deinit(self: *EditMemoryView) void {
        self.arena.deinit();
        if (self.memory) |*memory| {
            memory.*.deinit();
        }
    }
};
