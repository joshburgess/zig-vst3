const std = @import("std");
const vst3 = @import("zig-vst3");

pub const core = @import("zig-vst3-plugin-core");
pub const gui = @import("gui.zig");
pub const editor_state = core.editor_state;
pub const gui_preset_browser = core.gui_preset_browser;
pub const gui_telemetry = core.gui_telemetry;
pub const gui_graph = core.gui_graph;
pub const gui_piano = core.gui_piano;
pub const gui_step_sequencer = core.gui_step_sequencer;
pub const gui_file_drop = core.gui_file_drop;
pub const gui_file_importer = core.gui_file_importer;
pub const gui_audio_file_importer = core.gui_audio_file_importer;
pub const gui_audio_sample_store = core.gui_audio_sample_store;
pub const gui_sample_player = core.gui_sample_player;
pub const gui_ir_convolution = core.gui_ir_convolution;
pub const gui_ir_editor = core.gui_ir_editor;
pub const gui_progress = core.gui_progress;
pub const gui_range_selection = core.gui_range_selection;
pub const gui_viewport = core.gui_viewport;
pub const parameters = core.parameters;
pub const realtime_audit = core.realtime_audit;
pub const dsp = core.dsp;
pub const resource = core.resource;
pub const plugin = core.plugin;
pub const process = core.process;
pub const state = core.state;
pub const units = core.units;
pub const version = "0.2.1-dev";

pub fn backendVersion() []const u8 {
    return vst3.version;
}

test "zig-vst3-plugin sees zig-vst3" {
    try std.testing.expectEqualStrings("0.2.1-dev", backendVersion());
}

test "zig-vst3-plugin re-exports core modules" {
    try std.testing.expect(@hasDecl(parameters, "FloatParam"));
    try std.testing.expect(@hasDecl(realtime_audit, "Scope"));
    try std.testing.expect(@hasDecl(parameters, "LogFloatParam"));
    try std.testing.expect(@hasDecl(dsp, "SmoothedBiquad"));
    try std.testing.expect(@hasDecl(resource.job, "Job"));
    try std.testing.expect(@hasDecl(resource.exchange, "Exchange"));
    try std.testing.expect(@hasDecl(parameters, "normalizedFromBipolar"));
    try std.testing.expect(@hasDecl(plugin, "PluginSpec"));
    try std.testing.expect(@hasDecl(process, "ProcessContext"));
    try std.testing.expect(@hasDecl(state, "writeParameterState"));
    try std.testing.expect(@hasDecl(state, "format_version"));
    try std.testing.expect(@hasDecl(units, "UnitSet"));
    try std.testing.expect(@hasDecl(gui, "Editor"));
    try std.testing.expect(@hasDecl(editor_state, "Store"));
    try std.testing.expect(@hasDecl(gui_preset_browser, "Browser"));
    try std.testing.expect(@hasDecl(gui_telemetry, "ScalarSnapshot"));
    try std.testing.expect(@hasDecl(gui_graph, "SnapshotSeries"));
    try std.testing.expect(@hasDecl(gui_graph, "WaveformCapture"));
    try std.testing.expect(@hasDecl(gui_graph, "SpectrumAnalyzer"));
    try std.testing.expect(@hasDecl(gui_piano, "Keyboard"));
    try std.testing.expect(@hasDecl(gui_step_sequencer, "Sequencer"));
    try std.testing.expect(@hasDecl(gui_file_drop, "DropZone"));
    try std.testing.expect(@hasDecl(gui_file_importer, "Model"));
    try std.testing.expect(@hasDecl(gui_audio_file_importer, "Importer"));
    try std.testing.expect(@hasDecl(gui_audio_sample_store, "Store"));
    try std.testing.expect(@hasDecl(gui_sample_player, "Player"));
    try std.testing.expect(@hasDecl(gui_ir_convolution, "PartitionedConvolver"));
    try std.testing.expect(@hasDecl(gui_ir_editor, "Editor"));
    try std.testing.expect(@hasDecl(gui_progress, "Snapshot"));
    try std.testing.expect(@hasDecl(gui_range_selection, "State"));
    try std.testing.expect(@hasDecl(gui_viewport, "State"));
}

test "zig-vst3-plugin runs core module tests" {
    std.testing.refAllDecls(core);
}
