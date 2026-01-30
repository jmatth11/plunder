const std = @import("std");
const tui = @import("zigtui");

/// Cursor structure for a text field.
pub const Cursor = struct {
    /// The row
    row: u16 = 0,
    /// The column
    col: u16 = 0,
    /// Main theme
    theme: tui.Theme = tui.themes.dracula,
    /// Flag to toggle the cursor visibility.
    show: bool = false,
    /// Last toggled timestamp -- for blinking the cursor.
    last_toggled: i64 = 0,

    /// Set the cursor position with the given area.
    pub fn set_pos_from_area(self: *Cursor, area: tui.Rect) void {
        self.row = area.y;
        self.col = area.x;
    }
    /// Set the cursor position with the given row and column.
    pub fn set_pos(self: *Cursor, row: u16, col: u16) void {
        self.row = row;
        self.col = col;
    }

    /// Render cursor
    pub fn render(self: *Cursor, buf: *tui.render.Buffer) void {
        // blink logic
        const now = std.time.milliTimestamp();
        if ((now - self.last_toggled) > (std.time.ms_per_s * 1)) {
            self.last_toggled = std.time.milliTimestamp();
            self.show = !self.show;
        }
        if (self.show) {
            buf.setChar(self.col, self.row, ' ', self.theme.highlightStyle());
        }
    }
};

/// Search Bar subview.
pub const SearchBar = struct {
    /// main allocator
    alloc: std.mem.Allocator,
    /// Search buffer.
    search_buffer: [1024]u21 = @splat(0),
    /// The length of the search buffer.
    len: usize = 0,
    /// The Cursor within the view.
    cursor: Cursor = .{},
    /// main theme
    theme: tui.Theme = tui.themes.dracula,

    /// initialize
    pub fn init(alloc: std.mem.Allocator) SearchBar {
        return .{
            .alloc = alloc,
        };
    }

    /// Add a character to the search bar.
    pub fn add(self: *SearchBar, char: u21) void {
        if (self.len >= 1024) {
            return;
        }
        self.search_buffer[self.len] = char;
        self.len += 1;
    }

    /// Allocate a string of the internal search buffer.
    /// The user is responsible for freeing the returned value.
    ///
    /// @returns Null if the search buffer is empty, otherwise a newly allocated string.
    pub fn get_result(self: *SearchBar) !?[]const u8 {
        var result: std.array_list.Managed(u8) = .init(self.alloc);
        defer result.deinit();
        var codepoint_buffer: [4]u8 = @splat(0);
        for (0..self.len) |idx| {
            const len = try std.unicode.utf8Encode(self.search_buffer[idx], &codepoint_buffer);
            for (0..len) |codepoint_idx| {
                try result.append(codepoint_buffer[codepoint_idx]);
            }
        }
        if (result.items.len == 0) {
            return null;
        }
        return try result.toOwnedSlice();
    }

    /// Delete a character from the search buffer.
    pub fn delete(self: *SearchBar) void {
        if (self.len == 0) {
            return;
        }
        self.len -= 1;
    }

    /// Render the search bar.
    pub fn render(self: *SearchBar, area: tui.Rect, buf: *tui.render.Buffer) !void {
        const block: tui.widgets.Block = .{
            .title = " Search - [ESC] exit search; [ENTER] search ",
            .title_style = self.theme.titleStyle(),
            .border_symbols = tui.widgets.BorderSymbols.line(),
            .borders = tui.widgets.Borders.all(),
            .border_style = self.theme.borderFocusedStyle(),
            .style = self.theme.baseStyle(),
        };
        block.render(area, buf);
        const inner_block = block.inner(area);
        buf.fillArea(inner_block, ' ', self.theme.baseStyle());
        var offset_area = inner_block;
        const wrap_threshold = offset_area.x + offset_area.width;
        for (0..self.len) |idx| {
            const character = self.search_buffer[idx];
            buf.setChar(
                offset_area.x,
                offset_area.y,
                character,
                self.theme.textStyle(),
            );
            offset_area.x += 1;
            if (offset_area.x > wrap_threshold) {
                offset_area.x = inner_block.x;
                offset_area.y += 1;
            }
        }
        self.cursor.set_pos_from_area(offset_area);
        self.cursor.render(buf);
    }
};
