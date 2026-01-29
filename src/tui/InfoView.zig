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
    alloc: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    info_str: plunder.common.StringList,
    proc: ?plunder.proc.ProcInfo = null,
    selected: usize = 0,
    scroll_offset: usize = 0,
    tcp_list: ?[]plunder.network.NetworkInfo = null,
    udp_list: ?[]plunder.network.NetworkInfo = null,
    focused: bool = false,
    theme: tui.Theme = tui.themes.dracula,

    pub fn init(alloc: std.mem.Allocator) InfoView {
        return .{
            .alloc = alloc,
            .arena = .init(alloc),
            .info_str = .init(alloc),
        };
    }

    pub fn deinit(self: *InfoView) void {
        self.unload();
        self.arena.deinit();
    }

    pub fn render(self: *InfoView, area: tui.Rect, buf: *tui.render.Buffer) !void {
        const title = "Info View - [i] toggle back to Memory view";
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
            while (index < self.info_str.items.len and inner_block.y < actual_height) : (index += 1) {
                const line = self.info_str.items[index];
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
            const msg: tui.widgets.Paragraph = .{
                .text = "Press <ENTER> on a process to view it's info.",
                .style = self.theme.infoStyle(),
            };
            msg.render(inner_block, buf);
        }
    }

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
        self.info_str.clearAndFree();
        _ = self.arena.reset(.free_all);
    }

    pub fn next_selection(self: *InfoView) void {
        if (self.proc != null) {
            self.selected += 1;
            self.selected = self.selected % self.info_str.items.len;
        }
    }
    pub fn prev_selection(self: *InfoView) void {
        if (self.proc != null) {
            if (self.selected == 0) {
                self.selected = self.info_str.items.len - 1;
            } else {
                self.selected -= 1;
            }
        }
    }

    fn generate_info_str(self: *InfoView, arena: std.mem.Allocator) !void {
        if (self.proc) |proc| {
            const command = try std.fmt.allocPrint(arena, "Command: {s}", .{proc.command});
            try self.info_str.append(command);
            try self.info_str.append("Command Line Args:");
            var index: usize = 0;
            while (index < proc.command_line.len) : (index += 1) {
                const view = try proc.command_line.at(index);
                if (view.len == 0) continue;
                const arg = try std.fmt.allocPrint(
                    arena,
                    "- \"{s}\"",
                    .{view},
                );
                try self.info_str.append(arg);
            }
            try self.info_str.append(" ");
            try self.info_str.append("Environment Variables:");
            index = 0;
            while (index < proc.environment_vars.len) : (index += 1) {
                const view = try proc.environment_vars.at(index);
                if (view.len == 0) continue;
                const arg = try std.fmt.allocPrint(
                    arena,
                    "- \"{s}\"",
                    .{view},
                );
                try self.info_str.append(arg);
            }
            try self.info_str.append(" ");
            try self.info_str.append("------------------------------------");
            var buffer: [1024]u8 = undefined;
            var show_end_line: bool = false;
            if (self.tcp_list) |tcp_list| {
                if (tcp_list.len > 0) {
                    show_end_line = true;
                    try self.info_str.append(" ");
                    try self.info_str.append("TCP Connections");
                    try self.info_str.append("Type | State | Local Addr | Remote Addr | inode | Kernel Slot");
                    for (tcp_list) |tcp| {
                        var writer: std.io.Writer = .fixed(&buffer);
                        try tcp.format(&writer, false);
                        const line = try arena.dupe(u8, writer.buffer[0..writer.end]);
                        try self.info_str.append(line);
                    }
                }
            }
            if (self.udp_list) |udp_list| {
                if (udp_list.len > 0) {
                    show_end_line = true;
                    try self.info_str.append(" ");
                    try self.info_str.append("UDP Connections");
                    try self.info_str.append("Type | State | Local Addr | Remote Addr | inode | Kernel Slot");
                    for (udp_list) |udp| {
                        var writer: std.io.Writer = .fixed(&buffer);
                        try udp.format(&writer, false);
                        const line = try arena.dupe(u8, writer.buffer[0..writer.end]);
                        try self.info_str.append(line);
                    }
                }
            }
            if (show_end_line) {
                try self.info_str.append("------------------------------------");
            }
        }
    }
};
