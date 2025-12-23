const std = @import("std");
const dvui = @import("dvui");
const plunder = @import("plunder");
const CellStyle = dvui.GridWidget.CellStyle;

pub const ProcView = struct {
    alloc: std.mem.Allocator,
    list: plunder.proc.ProcList,
    initialized: bool = false,

    pub fn init(alloc: std.mem.Allocator) !ProcView {
        const result: ProcView = .{
            .alloc = alloc,
            .list = try plunder.proc.get_processes(alloc),
        };
        return result;
    }

    pub fn frame(self: *ProcView) !void {
        var outer_box = dvui.box(@src(), .{}, .{ .expand = .both });
        defer outer_box.deinit();
        {
            var top_controls = dvui.box(
                @src(),
                .{ .dir = .horizontal },
                .{ .gravity_y = 0 },
            );
            defer top_controls.deinit();
            dvui.labelNoFmt(
                @src(),
                "Filter",
                .{},
                .{ .margin = dvui.TextEntryWidget.defaults.margin },
            );
            var filter_name: []const u8 = "";
            var filter_changed: bool = false;
            var text = dvui.textEntry(@src(), .{}, .{ .expand = .horizontal });
            defer text.deinit();
            if (text.text_changed) {
                filter_name = text.textGet();
                filter_changed = true;
            }
        }
        var grid = dvui.grid(
            @src(),
            .numCols(3),
            .{ .scroll_opts = .{ .horizontal_bar = .auto } },
            .{ .expand = .both, .background = true },
        );
        defer grid.deinit();
        var highlight_style: CellStyle.HoveredRow = .{ .cell_opts = .{ .color_fill_hover = .gray, .background = true } };
        if (!self.initialized) {
            dvui.focusWidget(grid.data().id, null, null);
            self.initialized = true;
        }
        dvui.gridHeading(@src(), grid, 1, "PID", .fixed, .{});
        dvui.gridHeading(@src(), grid, 2, "Command", .fixed, .{});
        highlight_style.processEvents(grid);

        var single_select: dvui.selection.SingleSelect = .{};
        var selections: std.DynamicBitSet = try .initEmpty(self.alloc, self.list.procs.items.len);
        var selection_info: dvui.selection.SelectionInfo = .{};

        // Find out if any row was clicked on.
        const row_clicked: ?usize = blk: {
            for (dvui.events()) |*e| {
                if (!dvui.eventMatchSimple(e, grid.data())) continue;
                if (e.evt != .mouse) continue;
                const me = e.evt.mouse;
                if (me.action != .press) continue;
                if (grid.pointToCell(me.p)) |cell| {
                    if (cell.col_num > 0) break :blk cell.row_num;
                }
            }
            break :blk null;
        };

        selection_info.reset();
        for (self.list.procs.items, 0..) |proc, idx| {
            var cell_num: dvui.GridWidget.Cell = .colRow(0, idx);
            {
                defer cell_num.col_num += 1;
                var cell = grid.bodyCell(@src(), cell_num, highlight_style.cellOptions(cell_num));
                defer cell.deinit();
                var is_set = if (idx < selections.capacity()) selections.isSet(idx) else false;
                _ = dvui.checkboxEx(
                    @src(),
                    &is_set,
                    null,
                    .{ .selection_id = idx, .selection_info = &selection_info },
                    .{ .gravity_x = 0.5 },
                );
                // If this is the row that the user clicked on, add a selection event for it.
                if (idx == row_clicked) {
                    selection_info.add(idx, !is_set, cell.data());
                }
            }
            {
                defer cell_num.col_num += 1;
                var cell = grid.bodyCell(@src(), cell_num, highlight_style.cellOptions(cell_num));
                defer cell.deinit();
                dvui.label(@src(), "{}", .{proc.pid.?}, .{});
            }
            {
                defer cell_num.col_num += 1;
                var cell = grid.bodyCell(@src(), cell_num, highlight_style.cellOptions(cell_num));
                defer cell.deinit();
                dvui.labelNoFmt(@src(), proc.command, .{}, .{ .gravity_x = 1.0 });
            }
        }
        single_select.processEvents(&selection_info, grid.data());
        if (single_select.selectionChanged()) {
            if (single_select.id_to_unselect) |unselect_row| {
                selections.unset(unselect_row);
            }
            if (single_select.id_to_select) |select_row| {
                selections.set(select_row);
            }
        }
    }

    pub fn deinit(self: *ProcView) void {
        self.list.deinit();
    }
};
