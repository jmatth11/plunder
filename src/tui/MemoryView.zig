const std = @import("std");
const plunder = @import("plunder");
const tui = @import("zigtui");

pub const MemoryView = struct {
    alloc: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    theme: tui.Theme = tui.themes.dracula,
    focused: bool = false,
    proc: ?plunder.proc.ProcInfo = null,
    plun: plunder.Plunder,

    pub fn init(alloc: std.mem.Allocator) MemoryView {
        return .{
            .alloc = alloc,
            .plun = .init(alloc),
            .arena = .init(alloc),
        };
    }

    pub fn set_proc(self: *MemoryView, proc: plunder.proc.ProcInfo) !void {
        self.proc = proc;
        try self.plun.load(proc.pid);
    }

    pub fn render(self: *MemoryView, area: tui.Rect, buf: *tui.render.Buffer) !void {
        const arena = self.arena.allocator();
        _ = self.arena.reset(.free_all);
        const block: tui.widgets.Block = .{
            .style = self.theme.baseStyle(),
            .borders = tui.widgets.Borders.all(),
            .border_symbols = tui.widgets.BorderSymbols.double(),
            .border_style = if (self.focused) self.theme.borderFocusedStyle() else self.theme.borderStyle(),
            .title = "Memory View",
        };

        block.render(area, buf);

        if (self.proc != null) {
            const list = try self.plun.get_region_names(arena);
            _ = list;
        }
    }
};
