const std = @import("std");

/// Selection structure.
/// Keeps track of visual selection with the memory viewer.
pub const Selection = struct {
    start: usize = 0,
    end: usize = 0,
};

/// Position structure to track cursor position for entire buffer.
pub const Position = struct {
    row: usize = 0,
    col: usize = 0,

    /// Convert position into index into an array.
    /// This function assumes each line is a 16 byte hex dump.
    pub fn to_index(self: *const Position) usize {
        return (self.row * 16) + self.col;
    }
};

/// Calculate the scroll offset with the given information.
///
/// @param scroll_offset The current scroll offset
/// @param cur_pos The current position.
/// @param height The height of the given area.
/// @return The calculated scroll offset.
pub fn calculate_scroll_offset(scroll_offset: usize, cur_pos: usize, height: usize) usize {
    const scroll_offset_height = scroll_offset + height;
    // adjust to new positive offset
    if (cur_pos > scroll_offset_height) {
        return cur_pos - height;
    } else if (cur_pos < scroll_offset) {
        // adjust to new negative offset
        return cur_pos;
    }
    // keep the same
    return scroll_offset;
}

/// Check if character is printable.
pub fn is_printable(c: u21) bool {
    return (c >= 32 and c <= 126);
}
