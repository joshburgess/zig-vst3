const std = @import("std");
const common = @import("common.zig");

pub const parameters = @import("parameters.zig");
pub const editor_state = @import("editor_state.zig");
pub const gui_preset_browser = @import("gui_preset_browser.zig");
pub const gui_telemetry = @import("gui_telemetry.zig");
pub const gui_graph = @import("gui_graph.zig");
pub const gui_piano = @import("gui_piano.zig");
pub const gui_step_sequencer = @import("gui_step_sequencer.zig");
pub const plugin = @import("plugin.zig");
pub const process = @import("process.zig");
pub const state = @import("state.zig");
pub const units = @import("units.zig");

test {
    std.testing.refAllDecls(common);
    std.testing.refAllDecls(parameters);
    std.testing.refAllDecls(editor_state);
    std.testing.refAllDecls(gui_preset_browser);
    std.testing.refAllDecls(gui_telemetry);
    std.testing.refAllDecls(gui_graph);
    std.testing.refAllDecls(gui_piano);
    std.testing.refAllDecls(gui_step_sequencer);
    std.testing.refAllDecls(plugin);
    std.testing.refAllDecls(process);
    std.testing.refAllDecls(state);
    std.testing.refAllDecls(units);
}
