const std = @import("std");
const common = @import("common.zig");

pub const parameters = @import("parameters.zig");
pub const gui_telemetry = @import("gui_telemetry.zig");
pub const gui_graph = @import("gui_graph.zig");
pub const plugin = @import("plugin.zig");
pub const process = @import("process.zig");
pub const state = @import("state.zig");
pub const units = @import("units.zig");

test {
    std.testing.refAllDecls(common);
    std.testing.refAllDecls(parameters);
    std.testing.refAllDecls(gui_telemetry);
    std.testing.refAllDecls(gui_graph);
    std.testing.refAllDecls(plugin);
    std.testing.refAllDecls(process);
    std.testing.refAllDecls(state);
    std.testing.refAllDecls(units);
}
