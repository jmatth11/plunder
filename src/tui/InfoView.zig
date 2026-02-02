const std = @import("std");

const plunder = @import("plunder");
const tui = @import("zigtui");
const utils = @import("CommonUtils.zig");

/// Errors related to InfoView
pub const Errors = error{
    missing_process_id,
};

/// Info View structure
pub const InfoView = struct {
    /// Main allocator
    alloc: std.mem.Allocator,
    /// Arena allocator
    arena: std.heap.ArenaAllocator,
    /// Info string list
    info_str: plunder.common.StringListManager,
    /// The currently loaded process.
    proc: ?plunder.proc.ProcInfo = null,
    /// The line selected.
    selected: usize = 0,
    /// The scroll offset.
    scroll_offset: usize = 0,
    /// The TCP network info list.
    tcp_list: ?[]plunder.network.NetworkInfo = null,
    /// The UDP network info list.
    udp_list: ?[]plunder.network.NetworkInfo = null,
    /// Flag for the view being focused (controlled by parent)
    focused: bool = false,
    /// main theme
    theme: tui.Theme = tui.themes.dracula,

    /// initialize
    pub fn init(alloc: std.mem.Allocator) InfoView {
        return .{
            .alloc = alloc,
            .arena = .init(alloc),
            .info_str = .init(alloc),
        };
    }

    /// cleanup
    pub fn deinit(self: *InfoView) void {
        self.unload();
        self.arena.deinit();
        // we deinit manually since we are using an arena for all the internal strings.
        self.info_str.list.deinit();
    }

    /// Render info view
    pub fn render(self: *InfoView, area: tui.Rect, buf: *tui.render.Buffer) !void {
        const title = " Info View - [i] toggle back to Memory view ";
        const block: tui.widgets.Block = .{
            .style = self.theme.baseStyle(),
            .borders = tui.widgets.Borders.all(),
            .border_symbols = tui.widgets.BorderSymbols.double(),
            .border_style = if (self.focused) self.theme.borderFocusedStyle() else self.theme.borderStyle(),
            .title = title,
        };

        block.render(area, buf);
        var inner_block = block.inner(area);
        if (self.proc != null) {
            const offset_height = inner_block.height - 1;
            self.scroll_offset = utils.calculate_scroll_offset(
                self.scroll_offset,
                self.selected,
                offset_height,
            );
            var index: usize = self.scroll_offset;
            const actual_height = inner_block.y + inner_block.height;
            while (index < self.info_str.list.items.len and inner_block.y < actual_height) : (index += 1) {
                const line = self.info_str.list.items[index];
                if (index == self.selected) {
                    buf.setString(
                        inner_block.x,
                        inner_block.y,
                        line,
                        self.theme.highlightStyle(),
                    );
                } else {
                    buf.setString(
                        inner_block.x,
                        inner_block.y,
                        line,
                        self.theme.textStyle(),
                    );
                }
                inner_block.y += 1;
            }
        } else {
            // instruction message to display if a process isn't loaded.
            const msg: tui.widgets.Paragraph = .{
                .text = "Press <ENTER> on a process to view it's info.",
                .style = self.theme.infoStyle(),
            };
            msg.render(inner_block, buf);
        }
    }

    /// Load info for a new process.
    pub fn load(self: *InfoView, proc: plunder.proc.ProcInfo) !void {
        if (proc.pid == null) {
            return Errors.missing_process_id;
        }
        self.unload();
        self.selected = 0;
        self.scroll_offset = 0;
        self.proc = proc;
        self.tcp_list = plunder.network.get_tcp_info(self.alloc, proc.pid.?) catch null;
        self.udp_list = plunder.network.get_udp_info(self.alloc, proc.pid.?) catch null;
        try self.generate_info_str(self.arena.allocator());
    }

    /// Unload the current process.
    pub fn unload(self: *InfoView) void {
        self.proc = null;
        if (self.tcp_list) |tcp_list| {
            self.alloc.free(tcp_list);
            self.tcp_list = null;
        }
        if (self.udp_list) |udp_list| {
            self.alloc.free(udp_list);
            self.udp_list = null;
        }
        self.info_str.list.clearAndFree();
        _ = self.arena.reset(.free_all);
    }

    /// Next selection action.
    pub fn next_selection(self: *InfoView) void {
        if (self.proc != null) {
            self.selected += 1;
            self.selected = self.selected % self.info_str.list.items.len;
        }
    }
    /// Previous selection action.
    pub fn prev_selection(self: *InfoView) void {
        if (self.proc != null) {
            if (self.selected == 0) {
                self.selected = self.info_str.list.items.len - 1;
            } else {
                self.selected -= 1;
            }
        }
    }

    /// Generate the info string list to display.
    fn generate_info_str(self: *InfoView, arena: std.mem.Allocator) !void {
        if (self.proc) |proc| {
            const command = try std.fmt.allocPrint(arena, "Command: {s}", .{proc.command});
            try self.info_str.list.append(command);
            try self.info_str.list.append("Command Line Args:");
            var index: usize = 0;
            while (index < proc.command_line.len) : (index += 1) {
                const view = try proc.command_line.at(index);
                if (view.len == 0) continue;
                const arg = try std.fmt.allocPrint(
                    arena,
                    "- \"{s}\"",
                    .{view},
                );
                try self.info_str.list.append(arg);
            }
            try self.info_str.list.append(" ");
            try self.info_str.list.append("Environment Variables:");
            index = 0;
            while (index < proc.environment_vars.len) : (index += 1) {
                const view = try proc.environment_vars.at(index);
                if (view.len == 0) continue;
                const arg = try std.fmt.allocPrint(
                    arena,
                    "- \"{s}\"",
                    .{view},
                );
                try self.info_str.list.append(arg);
            }
            try self.info_str.list.append(" ");
            try self.info_str.list.append("------------------------------------");
            var buffer: [1024]u8 = undefined;
            var show_end_line: bool = false;
            if (self.tcp_list) |tcp_list| {
                if (tcp_list.len > 0) {
                    show_end_line = true;
                    try self.info_str.list.append(" ");
                    try self.info_str.list.append("TCP Connections");
                    try self.info_str.list.append("Type | State | Local Addr | Remote Addr | inode | Kernel Slot");
                    for (tcp_list) |tcp| {
                        var writer: std.io.Writer = .fixed(&buffer);
                        try tcp.format(&writer, false);
                        const line = try arena.dupe(u8, writer.buffer[0..writer.end]);
                        try self.info_str.list.append(line);
                    }
                }
            }
            if (self.udp_list) |udp_list| {
                if (udp_list.len > 0) {
                    show_end_line = true;
                    try self.info_str.list.append(" ");
                    try self.info_str.list.append("UDP Connections");
                    try self.info_str.list.append("Type | State | Local Addr | Remote Addr | inode | Kernel Slot");
                    for (udp_list) |udp| {
                        var writer: std.io.Writer = .fixed(&buffer);
                        try udp.format(&writer, false);
                        const line = try arena.dupe(u8, writer.buffer[0..writer.end]);
                        try self.info_str.list.append(line);
                    }
                }
            }
            if (show_end_line) {
                try self.info_str.list.append("------------------------------------");
            }
        }
    }
};
