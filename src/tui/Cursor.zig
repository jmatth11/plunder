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

