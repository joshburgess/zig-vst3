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

test "installed package exposes bounded resource commands" {
    try std.testing.expectEqual(@as(usize, 4096), vst3.resource_path_transport.maximum_path_bytes);
    try std.testing.expectEqual(
        vst3.pluginterfaces.base.types.kResultFalse,
        vst3.resource_path_transport.sendImport(null, 1, "model.nam"),
    );
    try std.testing.expectEqual(
        vst3.pluginterfaces.base.types.kResultFalse,
        vst3.resource_path_transport.sendCancel(null, 1),
    );
}

test "installed package exposes block boundary parameter latching" {
    var latch = plugin.process.BlockParameterLatch.init(12, 0.0);
    const changes = [_]plugin.process.ParameterChange{
        .{ .id = 12, .sample_offset = 0, .normalized = 0.25 },
        .{ .id = 12, .sample_offset = 3, .normalized = 0.75 },
    };
    const view = try plugin.process.ParameterChanges.init(&changes, 4);

    try std.testing.expectEqual(@as(f64, 0.25), latch.beginBlock(view, 0.75));
    try std.testing.expectEqual(@as(f64, 0.25), latch.valueAt(view, 2));
    try std.testing.expectEqual(@as(f64, 0.75), latch.valueAt(view, 3));
    try std.testing.expectEqual(@as(f64, 0.75), latch.nextBlockValue());
    try std.testing.expectEqual(@as(f64, 0.75), latch.beginBlock(.{}, 0.75));
}

test "installed package exposes toolkit-neutral GUI models" {
    const range = try plugin.gui_graph.Range.init(0.0, 1.0);
    const Envelope = plugin.gui_graph.EditableEnvelope(4);
    var envelope = try Envelope.init(range, range, .{}, &.{
        .{ .id = 1, .position = .{ .x = 0.0, .y = 0.0 } },
        .{ .id = 2, .position = .{ .x = 1.0, .y = 1.0 } },
    });
    try envelope.begin();
    _ = try envelope.add(.{ .x = 0.5, .y = 0.25 });
    envelope.finish();
    try std.testing.expect(envelope.valid());

    const viewport_config = plugin.gui_viewport.Config{ .initial_zoom = 2.0 };
    var viewport = try plugin.gui_viewport.State.init(viewport_config);
    try std.testing.expect(viewport.zoomIn(viewport_config, 0.5, 0.5));
    try std.testing.expect(viewport.valid(viewport_config));

    const selection_config = plugin.gui_range_selection.Config{
        .minimum = 0.0,
        .maximum = 1.0,
        .initial_start = 0.2,
        .initial_end = 0.8,
        .minimum_span = 0.1,
        .step = 0.01,
    };
    var selection = try plugin.gui_range_selection.State.init(selection_config);
    try std.testing.expect(selection.set(selection_config, .start, 0.3));
    try std.testing.expect(selection.valid(selection_config));

    const Presets = plugin.gui_preset_browser.Browser(2);
    var presets = Presets{};
    try presets.add(try plugin.gui_preset_browser.Preset.init(1, "Clean"));
    try presets.add(try plugin.gui_preset_browser.Preset.init(2, "Driven"));
    try presets.setSearch("drive");
    try std.testing.expectEqual(@as(usize, 1), presets.matchingCount());

    const reference = try plugin.resource.Reference(64, 32).init(
        "/models/example.nam",
        plugin.resource.Identity.fromBytes("fixture"),
        1,
        "Linear",
    );
    try std.testing.expectEqual(
        plugin.resource.RecoveryStatus.ready,
        reference.classifyCandidate("/models/example.nam", plugin.resource.Identity.fromBytes("fixture")),
    );
}
