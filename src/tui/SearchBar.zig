const std = @import("std");
const tui = @import("zigtui");
const cursor_view = @import("Cursor.zig");

/// Search Bar subview.
pub const SearchBar = struct {
    /// main allocator
    alloc: std.mem.Allocator,
    /// Search buffer.
    search_buffer: [1024]u21 = @splat(0),
    /// The length of the search buffer.
    len: usize = 0,
    /// The Cursor within the view.
    cursor: cursor_view.Cursor = .{},
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
