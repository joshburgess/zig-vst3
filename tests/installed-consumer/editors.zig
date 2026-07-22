const std = @import("std");
const vst3 = @import("zig-vst3");
const plugin = @import("zig-vst3-plugin");

const ui = vst3.vstgui;

const EffectParameters = struct {
    gain: plugin.parameters.FloatParam = .{
        .id = 0,
        .name = "Gain",
        .units = "dB",
        .min = -24.0,
        .max = 12.0,
        .default = 0.0,
    },
    bypass: plugin.parameters.BoolParam = .{
        .id = 1,
        .name = "Bypass",
        .default = false,
    },
};

const InstrumentParameters = struct {
    gain: plugin.parameters.FloatParam = .{
        .id = 0,
        .name = "Gain",
        .units = "dB",
        .min = -48.0,
        .max = 6.0,
        .default = 0.0,
    },
    pan: plugin.parameters.FloatParam = .{
        .id = 1,
        .name = "Pan",
        .min = -1.0,
        .max = 1.0,
        .default = 0.0,
    },
};

const MonoEffect = struct {
    pub const name = "Installed Mono Effect";
    pub const vendor = "Example Audio";
    pub const audio_input_layout: plugin.plugin.AudioBusLayout = .mono;
    pub const audio_output_layout: plugin.plugin.AudioBusLayout = .mono;
    pub const Params = EffectParameters;
};

const effect_editor: ui.EditorDescription = .{
    .parameters = &.{
        .{ .id = 0, .title = "Gain", .units = "dB", .step_count = 0, .default_normalized = 2.0 / 3.0, .control_kind = .decibel_slider },
        .{ .id = 1, .title = "Bypass", .step_count = 1, .default_normalized = 0.0, .control_kind = .toggle },
    },
    .graphs = &.{.{
        .title = "Transfer",
        .kind = .transfer_function,
        .x_axis = .{ .minimum = -1.0, .maximum = 1.0, .label = "Input" },
        .y_axis = .{ .minimum = -1.0, .maximum = 1.0, .label = "Output" },
        .points = &.{ .{ .x = -1.0, .y = -1.0 }, .{ .x = 0.0, .y = 0.0 }, .{ .x = 1.0, .y = 1.0 } },
    }},
    .skin = .{ .layout = .parameter_workspace },
    .composition = .{
        .title = "Installed Effect",
        .groups = &.{.{ .title = "Output", .parameter_count = 2, .graph_count = 1 }},
    },
};

const instrument_editor: ui.EditorDescription = .{
    .parameters = &.{
        .{ .id = 0, .title = "Gain", .units = "dB", .step_count = 0, .default_normalized = 8.0 / 9.0, .control_kind = .decibel_slider },
        .{ .id = 1, .title = "Pan", .step_count = 0, .default_normalized = 0.5, .control_kind = .bipolar_slider },
    },
    .graphs = &.{.{
        .title = "Sample",
        .kind = .waveform,
        .style = .modulation,
        .x_axis = .{ .minimum = 0.0, .maximum = 1.0, .label = "Time" },
        .y_axis = .{ .minimum = -1.0, .maximum = 1.0, .label = "Level" },
        .source_id = 100,
        .source = .controller,
        .dynamic = true,
        .maximum_refresh_hz = 30,
    }},
    .file_importers = &.{.{
        .id = 1,
        .title = "Sample",
        .prompt = "Drop a WAV or AIFF sample here",
        .picker_label = "Choose Sample",
        .picker_title = "Choose a Sample",
        .extensions = &.{ ".wav", ".aif", ".aiff" },
        .maximum_files = 1,
    }},
    .pianos = &.{.{ .title = "Audition", .first_note = 48, .note_count = 25 }},
    .skin = .{ .layout = .instrument_workspace },
    .composition = .{
        .title = "Installed Instrument",
        .groups = &.{.{ .title = "Playback", .parameter_count = 2, .graph_count = 1 }},
    },
};

test "installed package builds effect and instrument editor declarations" {
    const effect_set = plugin.parameters.ParameterSet(EffectParameters).init(.{});
    const instrument_set = plugin.parameters.ParameterSet(InstrumentParameters).init(.{});
    try std.testing.expectEqual(@as(usize, 2), @TypeOf(effect_set).count);
    try std.testing.expectEqual(@as(usize, 2), @TypeOf(instrument_set).count);
    try std.testing.expectEqual(@as(usize, 2), effect_editor.parameters.len);
    try std.testing.expectEqual(@as(usize, 1), effect_editor.graphs.len);
    try std.testing.expectEqual(@as(usize, 2), instrument_editor.parameters.len);
    try std.testing.expectEqual(@as(usize, 1), instrument_editor.file_importers.len);
    try std.testing.expectEqual(@as(usize, 1), instrument_editor.pianos.len);

    const mono_spec = plugin.plugin.PluginSpec(MonoEffect);
    try std.testing.expectEqual(plugin.plugin.AudioBusLayout.mono, mono_spec.audio_input_layout);
    try std.testing.expectEqual(@as(u8, 1), mono_spec.audio_output_layout.channelCount());
}
