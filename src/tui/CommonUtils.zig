const std = @import("std");

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
