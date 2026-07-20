const core = @import("zig-vst3-plugin-core");
const std = @import("std");
const vst3 = @import("zig-vst3");

const base = vst3.pluginterfaces.base;
const gui = vst3.pluginterfaces.gui;
const vst = vst3.pluginterfaces.vst;
const types = base.types;

pub const gain_param_id: u32 = 0;
pub const pan_param_id: u32 = 1;
pub const coarse_param_id: u32 = 2;
pub const fine_param_id: u32 = 3;
pub const start_param_id: u32 = 4;
pub const end_param_id: u32 = 5;
pub const loop_start_param_id: u32 = 6;
pub const loop_end_param_id: u32 = 7;
pub const loop_param_id: u32 = 8;
pub const reverse_param_id: u32 = 9;
pub const attack_param_id: u32 = 10;
pub const decay_param_id: u32 = 11;
pub const sustain_param_id: u32 = 12;
pub const release_param_id: u32 = 13;
pub const voices_param_id: u32 = 14;
pub const playback_param_id: u32 = 15;
pub const sample_import_id: u32 = 1;
pub const waveform_source_id: u32 = 100;
pub const playhead_source_id: u32 = 101;
pub const clear_action_group_id: u32 = 1;
pub const clear_action_id: u32 = 1;
pub const view_menu_id: u32 = 1;
pub const show_entire_sample_item_id: u32 = 1;
pub const zoom_playback_item_id: u32 = 2;
pub const zoom_loop_item_id: u32 = 3;
pub const maximum_sample_frames: usize = 262_144;
pub const maximum_voices: usize = 8;

const zoom_state_id: u32 = 1;
const x_offset_state_id: u32 = 2;
const last_import_state_id: u32 = 3;
const maximum_import_name_bytes: usize = 64;

pub const VoiceCount = enum { mono, two, four, eight };
pub const PlaybackMode = enum { gate, one_shot };
pub const VoiceCountParam = core.parameters.EnumParam(VoiceCount);
pub const PlaybackModeParam = core.parameters.EnumParam(PlaybackMode);

const Definition = struct {
    pub const name = "zig-vst3 Sample Player";
    pub const vendor = "zig-vst3";
    pub const url = "https://github.com/joshburgess/zig-vst3";
    pub const audio_input = false;
    pub const Params = struct {
        gain: core.parameters.FloatParam = .{ .id = gain_param_id, .name = "Gain", .units = "dB", .min = -60.0, .max = 12.0, .default = 0.0 },
        pan: core.parameters.FloatParam = .{ .id = pan_param_id, .name = "Pan", .units = "%", .min = -100.0, .max = 100.0, .default = 0.0 },
        coarse: core.parameters.FloatParam = .{ .id = coarse_param_id, .name = "Coarse", .units = "st", .min = -24.0, .max = 24.0, .default = 0.0 },
        fine: core.parameters.FloatParam = .{ .id = fine_param_id, .name = "Fine", .units = "cent", .min = -100.0, .max = 100.0, .default = 0.0 },
        start: core.parameters.FloatParam = .{ .id = start_param_id, .name = "Start", .units = "%", .min = 0.0, .max = 100.0, .default = 0.0 },
        end: core.parameters.FloatParam = .{ .id = end_param_id, .name = "End", .units = "%", .min = 0.0, .max = 100.0, .default = 100.0 },
        loop_start: core.parameters.FloatParam = .{ .id = loop_start_param_id, .name = "Loop Start", .units = "%", .min = 0.0, .max = 100.0, .default = 0.0 },
        loop_end: core.parameters.FloatParam = .{ .id = loop_end_param_id, .name = "Loop End", .units = "%", .min = 0.0, .max = 100.0, .default = 100.0 },
        loop: core.parameters.BoolParam = .{ .id = loop_param_id, .name = "Loop" },
        reverse: core.parameters.BoolParam = .{ .id = reverse_param_id, .name = "Reverse" },
        attack: core.parameters.LogFloatParam = .{ .id = attack_param_id, .name = "Attack", .units = "ms", .min = 0.1, .max = 5_000.0, .default = 5.0 },
        decay: core.parameters.LogFloatParam = .{ .id = decay_param_id, .name = "Decay", .units = "ms", .min = 0.1, .max = 5_000.0, .default = 80.0 },
        sustain: core.parameters.FloatParam = .{ .id = sustain_param_id, .name = "Sustain", .units = "%", .min = 0.0, .max = 100.0, .default = 80.0 },
        release: core.parameters.LogFloatParam = .{ .id = release_param_id, .name = "Release", .units = "ms", .min = 0.1, .max = 10_000.0, .default = 150.0 },
        voices: VoiceCountParam = .{ .id = voices_param_id, .name = "Voices", .default = .eight },
        playback: PlaybackModeParam = .{ .id = playback_param_id, .name = "Playback", .default = .gate },
    };
};

pub const Spec = core.plugin.PluginSpec(Definition);
pub const sample_parameter_set = Spec.ParameterSet.init(.{});
const AudioImporter = vst3.vstgui.DecodedAudioFileImporter(maximum_sample_frames);
const SamplePlayer = core.gui_sample_player.Player(maximum_sample_frames, maximum_voices);
const PlayheadSeries = core.gui_graph.SnapshotSeries(2);

const SamplePlayerEditorState = core.editor_state.Store(2, &.{
    .{ .id = zoom_state_id, .default = .{ .scalar = 1.0 } },
    .{ .id = x_offset_state_id, .default = .{ .scalar = 0.0 } },
    .{ .id = last_import_state_id, .default = .{ .text = .{} } },
});

const SamplePlayerControllerState = struct {
    importer: AudioImporter,
    published_import_generation: u64 = 0,
    transfer_generation: u64 = 0,
    pending_import_name: [maximum_import_name_bytes]u8 = @splat(0),
    pending_import_name_len: u8 = 0,

    pub fn init() SamplePlayerControllerState {
        return .{ .importer = .init() };
    }

    pub fn deinit(self: *SamplePlayerControllerState) void {
        self.importer.deinit();
    }
};

const Controller = vst3.zig_vst3_plugin_effect.ReflectedEditController(struct {
    pub const controller_name = "SamplePlayerController";
    pub const Params = Spec.Params;
    pub const parameter_set = &sample_parameter_set;
    pub const ControllerState = SamplePlayerControllerState;
    pub const EditorState = SamplePlayerEditorState;

    pub fn handleFileImport(
        controller: *vst.ivsteditcontroller.IEditController,
        import_id: u32,
        entry_point: vst3.vstgui.FileImportEntryPoint,
        paths: []const []const u8,
    ) types.tresult {
        if (import_id != sample_import_id or paths.len != 1) return types.kInvalidArgument;
        const state = Controller.controllerState(controller);
        if (!state.importer.begin(entry_point, paths)) return types.kResultFalse;
        const name = safeImportName(paths[0]);
        @memcpy(state.pending_import_name[0..name.len], name);
        state.pending_import_name_len = @intCast(name.len);
        return types.kResultOk;
    }

    pub fn loadFileImport(
        controller: *vst.ivsteditcontroller.IEditController,
        import_id: u32,
    ) ?vst3.vstgui.AudioFileImportSnapshot {
        if (import_id != sample_import_id) return null;
        const state = Controller.controllerState(controller);
        const snapshot = state.importer.snapshot();
        if (snapshot.import.status == .ready and snapshot.import.generation != state.published_import_generation) {
            const generation = state.transfer_generation +% 1;
            if (generation != 0 and Controller.sendDecodedAudioGeneration(controller, sample_import_id, generation, &state.importer) == types.kResultOk) {
                state.transfer_generation = generation;
                state.published_import_generation = snapshot.import.generation;
                const name = state.pending_import_name[0..state.pending_import_name_len];
                const text = core.editor_state.Text.init(name) catch return snapshot;
                Controller.editorState(controller).set(last_import_state_id, .{ .text = text }) catch return snapshot;
            }
        }
        return snapshot;
    }

    pub fn performFileImportCommand(
        controller: *vst.ivsteditcontroller.IEditController,
        import_id: u32,
        command: vst3.vstgui.FileImportCommand,
    ) types.tresult {
        if (import_id != sample_import_id) return types.kInvalidArgument;
        const state = Controller.controllerState(controller);
        const handled = switch (command) {
            .cancel => state.importer.requestCancel(),
            .retry => state.importer.retry(),
            .reset => clearSample(controller, state),
        };
        return if (handled) types.kResultOk else types.kResultFalse;
    }

    pub fn performAction(
        controller: *vst.ivsteditcontroller.IEditController,
        group_id: u32,
        action_id: u32,
    ) types.tresult {
        if (group_id != clear_action_group_id or action_id != clear_action_id) return types.kInvalidArgument;
        return if (clearSample(controller, Controller.controllerState(controller))) types.kResultOk else types.kResultFalse;
    }

    pub fn performMenuAction(
        controller: *vst.ivsteditcontroller.IEditController,
        menu_id: u32,
        item_id: u32,
        _: bool,
    ) types.tresult {
        if (menu_id != view_menu_id) return types.kInvalidArgument;
        return switch (item_id) {
            show_entire_sample_item_id => setViewport(controller, 0.0, 1.0),
            zoom_playback_item_id => setViewport(
                controller,
                Controller.getNormalized(controller, start_param_id),
                Controller.getNormalized(controller, end_param_id),
            ),
            zoom_loop_item_id => setViewport(
                controller,
                Controller.getNormalized(controller, loop_start_param_id),
                Controller.getNormalized(controller, loop_end_param_id),
            ),
            else => types.kInvalidArgument,
        };
    }

    pub fn loadGuiProgress(
        controller: *vst.ivsteditcontroller.IEditController,
        source_id: u32,
    ) ?core.gui_progress.Snapshot {
        if (source_id != sample_import_id) return null;
        const snapshot = Controller.controllerState(controller).importer.snapshot().import;
        return switch (snapshot.status) {
            .idle => .{ .generation = snapshot.generation },
            .validating => .{ .mode = .indeterminate, .state = .running, .generation = snapshot.generation },
            .importing => .{ .state = .running, .value = snapshot.progress(), .generation = snapshot.generation },
            .ready => .{ .state = .complete, .value = 1.0, .generation = snapshot.generation },
            else => .{ .state = .failed, .value = snapshot.progress(), .generation = snapshot.generation },
        };
    }

    pub fn loadGuiGraph(
        controller: *vst.ivsteditcontroller.IEditController,
        source_id: u32,
        output: []vst3.vstgui.GraphPoint,
    ) usize {
        if (source_id != waveform_source_id) return 0;
        var preview: [vst3.vstgui.audio_file_preview_capacity]vst3.vstgui.AudioFilePreviewPoint = undefined;
        const count = Controller.controllerState(controller).importer.copyPreview(&preview);
        const copied = @min(count, output.len);
        for (preview[0..copied], output[0..copied]) |point, *destination| destination.* = .{ .x = point.x, .y = point.y };
        return copied;
    }

    pub fn createView(
        controller: *vst.ivsteditcontroller.IEditController,
        name: types.FIDString,
    ) ?*gui.iplugview.IPlugView {
        return vst3.vstgui.createEditor(Controller, controller, name, .{
            .parameters = &.{
                control(start_param_id, "Start", "%", 0, defaultNormalized(start_param_id), .linear_slider),
                control(end_param_id, "End", "%", 0, defaultNormalized(end_param_id), .linear_slider),
                control(loop_start_param_id, "Loop Start", "%", 0, defaultNormalized(loop_start_param_id), .linear_slider),
                control(loop_end_param_id, "Loop End", "%", 0, defaultNormalized(loop_end_param_id), .linear_slider),
                control(gain_param_id, "Gain", "dB", 0, defaultNormalized(gain_param_id), .decibel_slider),
                control(pan_param_id, "Pan", "%", 0, defaultNormalized(pan_param_id), .bipolar_slider),
                control(coarse_param_id, "Coarse", "st", 0, defaultNormalized(coarse_param_id), .rotary_knob),
                control(fine_param_id, "Fine", "cent", 0, defaultNormalized(fine_param_id), .rotary_knob),
                control(loop_param_id, "Loop", "", 1, defaultNormalized(loop_param_id), .toggle),
                control(reverse_param_id, "Reverse", "", 1, defaultNormalized(reverse_param_id), .toggle),
                control(playback_param_id, "Playback", "", 1, defaultNormalized(playback_param_id), .segmented_enum),
                control(voices_param_id, "Voices", "", 3, defaultNormalized(voices_param_id), .segmented_enum),
                control(attack_param_id, "Attack", "ms", 0, defaultNormalized(attack_param_id), .rotary_knob),
                control(decay_param_id, "Decay", "ms", 0, defaultNormalized(decay_param_id), .rotary_knob),
                control(sustain_param_id, "Sustain", "%", 0, defaultNormalized(sustain_param_id), .rotary_knob),
                control(release_param_id, "Release", "ms", 0, defaultNormalized(release_param_id), .rotary_knob),
            },
            .graphs = &.{.{
                .title = "Sample Waveform",
                .kind = .waveform,
                .style = .modulation,
                .x_axis = .{ .minimum = 0.0, .maximum = 1.0, .label = "Time" },
                .y_axis = .{ .minimum = -1.0, .maximum = 1.0, .label = "Level" },
                .source_id = waveform_source_id,
                .source = .controller,
                .dynamic = true,
                .maximum_refresh_hz = 30,
                .viewport = .{ .maximum_zoom = 128.0, .zoom_state_id = zoom_state_id, .x_offset_state_id = x_offset_state_id },
                .range_selection = .{
                    .minimum_span = 1.0 / @as(f64, maximum_sample_frames),
                    .step = 1.0 / 1024.0,
                    .start_parameter_id = start_param_id,
                    .end_parameter_id = end_param_id,
                },
                .secondary_range_selection = .{
                    .minimum_span = 1.0 / @as(f64, maximum_sample_frames),
                    .step = 1.0 / 1024.0,
                    .start_parameter_id = loop_start_param_id,
                    .end_parameter_id = loop_end_param_id,
                },
                .layers = &.{.{
                    .style = .warning,
                    .kind = .waveform,
                    .source_id = playhead_source_id,
                    .dynamic = true,
                }},
            }},
            .file_importers = &.{.{
                .id = sample_import_id,
                .title = "Sample",
                .prompt = "Drop a PCM WAV or AIFF sample here",
                .picker_label = "Choose Sample",
                .picker_title = "Choose a Sample",
                .extensions = &.{ ".wav", ".aif", ".aiff" },
                .maximum_files = 1,
            }},
            .progress_indicators = &.{.{
                .source_id = sample_import_id,
                .label = "Import",
                .accessible_label = "Sample import progress",
                .idle_text = "Choose a sample to begin",
                .running_text = "Importing sample",
                .complete_text = "Sample ready",
                .failure_text = "Import failed. Retry or choose another file",
            }},
            .action_buttons = &.{.{
                .group_id = clear_action_group_id,
                .id = clear_action_id,
                .icon = .clear,
                .accessible_label = "Clear sample",
                .tooltip = "Remove the imported sample.",
                .confirmation_label = "Confirm Clear Sample",
                .failure_label = "Clear failed. Try again",
                .role = .destructive,
                .success_focus_importer_id = sample_import_id,
                .ready_importer_id = sample_import_id,
            }},
            .action_menus = &.{.{
                .id = view_menu_id,
                .title = "View",
                .items = &.{
                    .{ .id = show_entire_sample_item_id, .label = "Show Entire Sample" },
                    .{ .id = zoom_playback_item_id, .label = "Zoom to Playback Range" },
                    .{ .id = zoom_loop_item_id, .label = "Zoom to Loop Range" },
                },
            }},
            .editable_labels = &.{.{
                .field_id = last_import_state_id,
                .label = "Last Import",
                .accessible_label = "Last imported sample",
                .placeholder = "No previous sample",
                .error_text = "Import name unavailable",
                .maximum_bytes = maximum_import_name_bytes,
                .read_only = true,
                .maximum_refresh_hz = 10,
            }},
            .pianos = &.{.{ .title = "Sample Keyboard", .first_note = 48, .note_count = 25, .computer_base_pitch = 60 }},
            .skin = .{ .theme = .default, .layout = .instrument_workspace },
            .composition = .{
                .title = "Sample Player",
                .style = .{ .background = 0x111922ff, .foreground = 0xeaf3f6ff, .accent = 0x52d5b0ff },
                .groups = &.{
                    .{ .title = "Waveform", .parameter_count = 2, .graph_count = 1, .style = .{ .accent = 0x79baf2ff } },
                    .{ .title = "Loop Range", .first_parameter = 2, .parameter_count = 2, .first_graph = 1, .style = .{ .accent = 0x79baf2ff } },
                    .{ .title = "Playback", .first_parameter = 4, .parameter_count = 4, .first_graph = 1, .style = .{ .accent = 0x52d5b0ff } },
                    .{ .title = "Mode and Voices", .first_parameter = 8, .parameter_count = 4, .first_graph = 1, .style = .{ .accent = 0xf0ad65ff } },
                    .{ .title = "Envelope", .first_parameter = 12, .parameter_count = 4, .first_graph = 1, .style = .{ .accent = 0xc58be8ff } },
                },
            },
        });
    }

    fn clearSample(controller: *vst.ivsteditcontroller.IEditController, state: *SamplePlayerControllerState) bool {
        if (!state.importer.canReset()) return false;
        const generation = state.transfer_generation +% 1;
        if (generation == 0 or Controller.clearDecodedAudio(controller, sample_import_id, generation) != types.kResultOk) return false;
        if (!state.importer.reset()) return false;
        Controller.editorState(controller).reset(last_import_state_id) catch return false;
        state.pending_import_name_len = 0;
        state.transfer_generation = generation;
        state.published_import_generation = 0;
        return true;
    }

    fn setViewport(controller: *vst.ivsteditcontroller.IEditController, first: f64, second: f64) types.tresult {
        if (!std.math.isFinite(first) or !std.math.isFinite(second)) return types.kInvalidArgument;
        const start = std.math.clamp(@min(first, second), 0.0, 1.0);
        const end = std.math.clamp(@max(first, second), 0.0, 1.0);
        const minimum_span = 1.0 / @as(f64, maximum_sample_frames);
        const zoom = std.math.clamp(1.0 / @max(end - start, minimum_span), 1.0, 128.0);
        const visible_span = 1.0 / zoom;
        const offset = std.math.clamp((start + end - visible_span) * 0.5, 0.0, 1.0 - visible_span);
        const state = Controller.editorState(controller);
        state.set(zoom_state_id, .{ .scalar = zoom }) catch return types.kResultFalse;
        state.set(x_offset_state_id, .{ .scalar = offset }) catch return types.kResultFalse;
        return types.kResultOk;
    }
});

const SamplePlayerProcessor = struct {
    player: SamplePlayer,
    playhead: PlayheadSeries,

    pub fn initInPlace(self: *SamplePlayerProcessor) void {
        self.player = .{};
        self.playhead = PlayheadSeries.init();
    }

    pub fn prepare(self: *SamplePlayerProcessor, config: core.plugin.PrepareConfig) void {
        self.player.prepare(config.sample_rate);
    }

    pub fn reset(self: *SamplePlayerProcessor) void {
        self.player.reset();
    }

    pub fn audioImportReceiver(self: *SamplePlayerProcessor) *core.gui_audio_sample_store.Store(maximum_sample_frames) {
        return self.player.audioImportReceiver();
    }

    pub fn process(
        self: *SamplePlayerProcessor,
        _: anytype,
        comptime Sample: type,
        context: *core.process.ProcessContext(Sample),
    ) void {
        context.clearOutputs();
        _ = self.player.adoptPending();
        var segments = context.processBlockSegments();
        while (segments.next()) |segment| {
            const playback = playbackAt(context, segment.start_offset);
            var events = context.inputEventsAtOffset(segment.start_offset);
            while (events.next()) |event| {
                if (event.asNoteAttack()) |note| {
                    self.player.noteOn(note.pitch, note.velocity, playback);
                } else if (event.asNoteRelease()) |note| {
                    self.player.noteOff(note.pitch, playback);
                }
            }
            for (segment.start_offset..segment.end_offset) |sample| {
                const frame = self.player.processFrame(playback);
                if (context.outputChannel(0)) |output| output[sample] = @floatCast(frame[0]);
                if (context.outputChannel(1)) |output| output[sample] = @floatCast(frame[1]);
            }
        }
        if (self.player.playhead()) |position| {
            _ = self.playhead.publish(&.{ .{ .x = position, .y = -1.0 }, .{ .x = position, .y = 1.0 } });
        } else {
            _ = self.playhead.publish(&.{});
        }
    }

    pub fn guiGraphLoad(self: *SamplePlayerProcessor, source_id: u32, output: []core.gui_graph.Point) usize {
        if (source_id != playhead_source_id) return 0;
        return self.playhead.read(output) orelse 0;
    }

    pub fn guiTelemetryEditorOpened(self: *SamplePlayerProcessor) void {
        self.playhead.editorOpened();
    }

    pub fn guiTelemetryEditorClosed(self: *SamplePlayerProcessor) void {
        self.playhead.editorClosed();
    }
};

const Effect = vst3.zig_vst3_plugin_effect.SimpleStereoEffect(struct {
    pub const component_name = "SamplePlayerComponent";
    pub const controller_cid = sample_player_controller_cid;
    pub const event_input = Spec.event_input;
    pub const gui_note_input = true;
    pub const audio_input = Spec.audio_input;
    pub const Params = Spec.Params;
    pub const parameter_set = &sample_parameter_set;
    pub const audio_import_target_id = sample_import_id;
    pub const Processor = SamplePlayerProcessor;
});

pub const component_cid = vst3.tuid.inlineUid(0xB110C621, 0x4D9D4B10, 0xAD0831CB, 0x11274A90);
pub const sample_player_controller_cid = vst3.tuid.inlineUid(0x92F06B17, 0xA23E49B8, 0x8A55E20F, 0x665302D1);

const Factory = vst3.factory.StaticFactory3(.{
    .vendor = Spec.vendor,
    .url = Spec.url,
    .email = Spec.email,
}, &.{
    .{ .cid = component_cid, .category = Spec.component_category, .name = Spec.component_class_name, .create = Effect.create },
    .{ .cid = sample_player_controller_cid, .category = Spec.controller_category, .name = Spec.controller_class_name, .create = Controller.create },
});

comptime {
    vst3.entry.exportPlugin(Factory);
}

fn control(
    id: u32,
    title: [*:0]const u8,
    units: [*:0]const u8,
    step_count: i32,
    default_normalized: f64,
    kind: @TypeOf(@as(vst3.vstgui.Parameter, undefined).control_kind),
) vst3.vstgui.Parameter {
    return .{ .id = id, .title = title, .units = units, .step_count = step_count, .default_normalized = default_normalized, .control_kind = kind, .tooltip = tooltip(id) };
}

fn tooltip(id: u32) [*:0]const u8 {
    return switch (id) {
        gain_param_id => "Adjust sample output level.",
        pan_param_id => "Place the sample between the left and right channels.",
        coarse_param_id => "Transpose playback in semitones.",
        fine_param_id => "Fine tune playback in cents.",
        start_param_id => "Set the first playable sample position.",
        end_param_id => "Set the last playable sample position.",
        loop_start_param_id => "Set the loop start inside the playable range.",
        loop_end_param_id => "Set the loop end inside the playable range.",
        loop_param_id => "Repeat playback between the loop markers.",
        reverse_param_id => "Play from the end toward the start.",
        attack_param_id => "Set the amplitude fade-in time.",
        decay_param_id => "Set the time to reach the sustain level.",
        sustain_param_id => "Set the held amplitude level.",
        release_param_id => "Set the fade-out time after note release.",
        voices_param_id => "Set the maximum simultaneous voices.",
        playback_param_id => "Gate follows note release; One Shot plays to the end.",
        else => "Adjust this sample-player parameter.",
    };
}

fn defaultNormalized(id: u32) f64 {
    return sample_parameter_set.defaultNormalizedById(id) orelse 0.0;
}

fn safeImportName(path: []const u8) []const u8 {
    const separator = std.mem.lastIndexOfAny(u8, path, "/\\");
    const name = if (separator) |index| path[index + 1 ..] else path;
    if (!std.unicode.utf8ValidateSlice(name)) return "";
    var end = @min(name.len, maximum_import_name_bytes);
    while (end > 0 and !std.unicode.utf8ValidateSlice(name[0..end])) end -= 1;
    return name[0..end];
}

fn playbackAt(context: anytype, sample_offset: usize) core.gui_sample_player.Playback {
    const voices = (VoiceCountParam{ .id = voices_param_id, .name = "Voices", .default = .eight }).denormalize(normalizedAt(context, voices_param_id, sample_offset));
    const mode = (PlaybackModeParam{ .id = playback_param_id, .name = "Playback", .default = .gate }).denormalize(normalizedAt(context, playback_param_id, sample_offset));
    const gain_db = plainAt(context, gain_param_id, sample_offset, 0.0);
    return .{
        .gain = std.math.pow(f64, 10.0, gain_db / 20.0),
        .pan = plainAt(context, pan_param_id, sample_offset, 0.0) / 100.0,
        .coarse_semitones = plainAt(context, coarse_param_id, sample_offset, 0.0),
        .fine_cents = plainAt(context, fine_param_id, sample_offset, 0.0),
        .start = plainAt(context, start_param_id, sample_offset, 0.0) / 100.0,
        .end = plainAt(context, end_param_id, sample_offset, 100.0) / 100.0,
        .loop_start = plainAt(context, loop_start_param_id, sample_offset, 0.0) / 100.0,
        .loop_end = plainAt(context, loop_end_param_id, sample_offset, 100.0) / 100.0,
        .loop_enabled = normalizedAt(context, loop_param_id, sample_offset) >= 0.5,
        .reverse = normalizedAt(context, reverse_param_id, sample_offset) >= 0.5,
        .release_on_note_off = mode == .gate,
        .voice_limit = switch (voices) {
            .mono => 1,
            .two => 2,
            .four => 4,
            .eight => 8,
        },
        .envelope = .{
            .attack_seconds = plainAt(context, attack_param_id, sample_offset, 5.0) / 1_000.0,
            .decay_seconds = plainAt(context, decay_param_id, sample_offset, 80.0) / 1_000.0,
            .sustain = plainAt(context, sustain_param_id, sample_offset, 80.0) / 100.0,
            .release_seconds = plainAt(context, release_param_id, sample_offset, 150.0) / 1_000.0,
        },
    };
}

fn normalizedAt(context: anytype, id: u32, sample_offset: usize) f64 {
    return context.parameterNormalizedAtOrBeforeOr(id, sample_offset, defaultNormalized(id));
}

fn plainAt(context: anytype, id: u32, sample_offset: usize, fallback: f64) f64 {
    return sample_parameter_set.plainFromNormalizedById(id, normalizedAt(context, id, sample_offset)) orelse fallback;
}

fn writeTestWav(directory: *std.Io.Dir, sub_path: []const u8, frame_count: usize, sample: i16) !void {
    const io = std.testing.io;
    var file = try directory.createFile(io, sub_path, .{});
    defer file.close(io);
    var header: [44]u8 = undefined;
    var writer = std.Io.Writer.fixed(&header);
    try writer.writeAll("RIFF");
    try writer.writeInt(u32, @intCast(36 + frame_count * 2), .little);
    try writer.writeAll("WAVEfmt ");
    try writer.writeInt(u32, 16, .little);
    try writer.writeInt(u16, 1, .little);
    try writer.writeInt(u16, 1, .little);
    try writer.writeInt(u32, 48_000, .little);
    try writer.writeInt(u32, 96_000, .little);
    try writer.writeInt(u16, 2, .little);
    try writer.writeInt(u16, 16, .little);
    try writer.writeAll("data");
    try writer.writeInt(u32, @intCast(frame_count * 2), .little);
    try file.writeStreamingAll(io, writer.buffered());
    var samples: [1024]i16 = @splat(sample);
    var remaining = frame_count;
    while (remaining > 0) {
        const count = @min(remaining, samples.len);
        try file.writeStreamingAll(io, std.mem.sliceAsBytes(samples[0..count]));
        remaining -= count;
    }
}

fn waitForSampleImport(controller: *vst.ivsteditcontroller.IEditController) !vst3.vstgui.AudioFileImportSnapshot {
    var attempts: usize = 0;
    while (attempts < 1_000_000) : (attempts += 1) {
        const snapshot = Controller.loadFileImport(controller, sample_import_id) orelse return error.MissingImportState;
        if (snapshot.import.status == .ready) return snapshot;
        if (snapshot.import.status != .validating and snapshot.import.status != .importing) return error.ImportFailed;
        std.Thread.yield() catch {};
    }
    return error.ImportTimedOut;
}

test "sample player exports component and controller classes" {
    const factory = Factory.getPluginFactory() orelse return error.MissingFactory;
    try std.testing.expectEqual(@as(i32, 2), factory.vtable.countClasses(factory));
}

test "sample player creates its public API editor" {
    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Controller.create(@ptrCast(&vst.ivsteditcontroller.iedit_controller_iid), &out));
    const controller: *vst.ivsteditcontroller.IEditController = @ptrCast(@alignCast(out orelse return error.MissingController));
    defer _ = controller.vtable.release(controller);
    try std.testing.expectEqual(@as(i32, 16), controller.vtable.getParameterCount(controller));
    const view = controller.vtable.createView(controller, vst.ivsteditcontroller.ViewType.kEditor) orelse return error.MissingEditorView;
    defer _ = view.vtable.release(view);
}

test "sample player creates isolated responsive editor views" {
    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Controller.create(@ptrCast(&vst.ivsteditcontroller.iedit_controller_iid), &out));
    const controller: *vst.ivsteditcontroller.IEditController = @ptrCast(@alignCast(out orelse return error.MissingController));
    defer _ = controller.vtable.release(controller);
    const first = controller.vtable.createView(controller, vst.ivsteditcontroller.ViewType.kEditor) orelse return error.MissingEditorView;
    defer _ = first.vtable.release(first);
    const second = controller.vtable.createView(controller, vst.ivsteditcontroller.ViewType.kEditor) orelse return error.MissingEditorView;
    defer _ = second.vtable.release(second);
    try std.testing.expect(first != second);
    var initial_second_size = gui.iplugview.ViewRect{};
    try std.testing.expectEqual(types.kResultOk, second.vtable.getSize(second, &initial_second_size));
    var compact = gui.iplugview.ViewRect{ .left = 0, .top = 0, .right = 480, .bottom = 480 };
    try std.testing.expectEqual(types.kResultOk, first.vtable.onSize(first, &compact));
    var second_size = gui.iplugview.ViewRect{};
    try std.testing.expectEqual(types.kResultOk, second.vtable.getSize(second, &second_size));
    try std.testing.expectEqual(initial_second_size.right, second_size.right);
    try std.testing.expectEqual(initial_second_size.bottom, second_size.bottom);
}

test "sample player stores only a bounded import name" {
    try std.testing.expectEqualStrings("snare.aiff", safeImportName("/Users/test/Samples/snare.aiff"));
    try std.testing.expectEqualStrings("kick.wav", safeImportName("C:\\Samples\\kick.wav"));
    const long_name = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-long.wav";
    try std.testing.expectEqual(maximum_import_name_bytes, safeImportName(long_name).len);
    const unicode_name = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ012345678é.wav";
    const bounded_unicode = safeImportName(unicode_name);
    try std.testing.expect(bounded_unicode.len <= maximum_import_name_bytes);
    try std.testing.expect(std.unicode.utf8ValidateSlice(bounded_unicode));
    try std.testing.expectEqualStrings("", safeImportName("bad-\xff.wav"));
}

test "sample player restores version one editor state with empty media metadata" {
    const VersionOne = core.editor_state.Store(1, &.{
        .{ .id = zoom_state_id, .default = .{ .scalar = 1.0 } },
        .{ .id = x_offset_state_id, .default = .{ .scalar = 0.0 } },
    });
    var previous = VersionOne.init();
    try previous.set(zoom_state_id, .{ .scalar = 4.0 });
    try previous.set(x_offset_state_id, .{ .scalar = 0.25 });
    var bytes: [VersionOne.maximumEncodedSize()]u8 = undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    try previous.write(&writer);

    var reader = std.Io.Reader.fixed(writer.buffered());
    var restored = SamplePlayerEditorState.init();
    const report = try restored.read(&reader, &.{});
    try std.testing.expectEqual(@as(u16, 1), report.source_schema_version);
    try std.testing.expectEqual(@as(f64, 4.0), restored.get(zoom_state_id).?.scalar);
    try std.testing.expectEqual(@as(f64, 0.25), restored.get(x_offset_state_id).?.scalar);
    try std.testing.expectEqualStrings("", restored.get(last_import_state_id).?.text.slice());
}

test "sample player controller state restores without hidden media access" {
    var first_out: ?*anyopaque = null;
    var second_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Controller.create(@ptrCast(&vst.ivsteditcontroller.iedit_controller_iid), &first_out));
    try std.testing.expectEqual(types.kResultOk, Controller.create(@ptrCast(&vst.ivsteditcontroller.iedit_controller_iid), &second_out));
    const first: *vst.ivsteditcontroller.IEditController = @ptrCast(@alignCast(first_out orelse return error.MissingController));
    defer _ = first.vtable.release(first);
    const second: *vst.ivsteditcontroller.IEditController = @ptrCast(@alignCast(second_out orelse return error.MissingController));
    defer _ = second.vtable.release(second);

    try Controller.editorState(first).set(zoom_state_id, .{ .scalar = 8.0 });
    try Controller.editorState(first).set(x_offset_state_id, .{ .scalar = 0.375 });
    try Controller.editorState(first).set(last_import_state_id, .{ .text = try core.editor_state.Text.init("isolated.wav") });
    try std.testing.expectEqual(@as(f64, 1.0), Controller.editorState(second).get(zoom_state_id).?.scalar);
    try std.testing.expectEqualStrings("", Controller.editorState(second).get(last_import_state_id).?.text.slice());

    const Stream = vst3.vst_stream.FixedBufferStream(65_536);
    var stream = Stream{};
    try std.testing.expectEqual(types.kResultOk, first.vtable.getState(first, stream.asStream()));
    try std.testing.expectEqual(types.kResultOk, stream.asStream().vtable.seek(
        stream.asStream(),
        0,
        @intFromEnum(base.ibstream.IStreamSeekMode.kIBSeekSet),
        null,
    ));
    try std.testing.expectEqual(types.kResultOk, second.vtable.setState(second, stream.asStream()));
    try std.testing.expectEqual(@as(f64, 8.0), Controller.editorState(second).get(zoom_state_id).?.scalar);
    try std.testing.expectEqual(@as(f64, 0.375), Controller.editorState(second).get(x_offset_state_id).?.scalar);
    try std.testing.expectEqualStrings("isolated.wav", Controller.editorState(second).get(last_import_state_id).?.text.slice());
    try std.testing.expectEqual(
        core.gui_file_importer.Status.idle,
        (Controller.loadFileImport(second, sample_import_id) orelse return error.MissingImportState).import.status,
    );
    var graph: [vst3.vstgui.audio_file_preview_capacity]vst3.vstgui.GraphPoint = undefined;
    try std.testing.expectEqual(@as(usize, 0), Controller.loadGuiGraph(second, waveform_source_id, &graph));
}

test "sample player view menu frames playback and loop ranges" {
    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Controller.create(@ptrCast(&vst.ivsteditcontroller.iedit_controller_iid), &out));
    const controller: *vst.ivsteditcontroller.IEditController = @ptrCast(@alignCast(out orelse return error.MissingController));
    defer _ = controller.vtable.release(controller);
    try std.testing.expectEqual(types.kResultOk, Controller.setNormalized(controller, start_param_id, 0.25));
    try std.testing.expectEqual(types.kResultOk, Controller.setNormalized(controller, end_param_id, 0.75));
    try std.testing.expectEqual(types.kResultOk, Controller.performMenuAction(
        controller,
        view_menu_id,
        zoom_playback_item_id,
        false,
    ));
    try std.testing.expectEqual(@as(f64, 2.0), Controller.editorState(controller).get(zoom_state_id).?.scalar);
    try std.testing.expectEqual(@as(f64, 0.25), Controller.editorState(controller).get(x_offset_state_id).?.scalar);

    try std.testing.expectEqual(types.kResultOk, Controller.performMenuAction(
        controller,
        view_menu_id,
        show_entire_sample_item_id,
        false,
    ));
    try std.testing.expectEqual(@as(f64, 1.0), Controller.editorState(controller).get(zoom_state_id).?.scalar);
    try std.testing.expectEqual(@as(f64, 0.0), Controller.editorState(controller).get(x_offset_state_id).?.scalar);
    try std.testing.expectEqual(types.kInvalidArgument, Controller.performMenuAction(controller, view_menu_id, 99, false));
}

test "sample player controller imports remain instance isolated" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try writeTestWav(&temporary.dir, "isolated.wav", 32, 8_000);
    var path: [1024]u8 = undefined;
    const path_length = try temporary.dir.realPathFile(std.testing.io, "isolated.wav", &path);
    var first_out: ?*anyopaque = null;
    var second_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Controller.create(@ptrCast(&vst.ivsteditcontroller.iedit_controller_iid), &first_out));
    try std.testing.expectEqual(types.kResultOk, Controller.create(@ptrCast(&vst.ivsteditcontroller.iedit_controller_iid), &second_out));
    const first: *vst.ivsteditcontroller.IEditController = @ptrCast(@alignCast(first_out orelse return error.MissingController));
    defer _ = first.vtable.release(first);
    const second: *vst.ivsteditcontroller.IEditController = @ptrCast(@alignCast(second_out orelse return error.MissingController));
    defer _ = second.vtable.release(second);
    try std.testing.expectEqual(types.kResultOk, Controller.handleFileImport(
        first,
        sample_import_id,
        .picker,
        &.{path[0..path_length]},
    ));
    const first_snapshot = try waitForSampleImport(first);
    try std.testing.expectEqual(@as(usize, 32), first_snapshot.decoded_frames);
    try std.testing.expectEqual(
        core.gui_file_importer.Status.idle,
        (Controller.loadFileImport(second, sample_import_id) orelse return error.MissingImportState).import.status,
    );
    var graph: [vst3.vstgui.audio_file_preview_capacity]vst3.vstgui.GraphPoint = undefined;
    try std.testing.expect(Controller.loadGuiGraph(first, waveform_source_id, &graph) > 0);
    try std.testing.expectEqual(@as(usize, 0), Controller.loadGuiGraph(second, waveform_source_id, &graph));
}

test "sample player controller joins pending import during teardown" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try writeTestWav(&temporary.dir, "pending.wav", maximum_sample_frames, 4_000);
    var path: [1024]u8 = undefined;
    const path_length = try temporary.dir.realPathFile(std.testing.io, "pending.wav", &path);
    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Controller.create(@ptrCast(&vst.ivsteditcontroller.iedit_controller_iid), &out));
    const controller: *vst.ivsteditcontroller.IEditController = @ptrCast(@alignCast(out orelse return error.MissingController));
    try std.testing.expectEqual(types.kResultOk, Controller.handleFileImport(
        controller,
        sample_import_id,
        .picker,
        &.{path[0..path_length]},
    ));
    _ = controller.vtable.release(controller);
}

test "sample player replaces imports across editor teardown and clears the processor" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try writeTestWav(&temporary.dir, "first.wav", 64, 12_000);
    try writeTestWav(&temporary.dir, "replacement.wav", 64, -12_000);
    var first_path: [1024]u8 = undefined;
    const first_length = try temporary.dir.realPathFile(std.testing.io, "first.wav", &first_path);
    var replacement_path: [1024]u8 = undefined;
    const replacement_length = try temporary.dir.realPathFile(std.testing.io, "replacement.wav", &replacement_path);

    var component_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Effect.create(@ptrCast(&vst.ivstcomponent.icomponent_iid), &component_out));
    const component: *vst.ivstcomponent.IComponent = @ptrCast(@alignCast(component_out orelse return error.MissingComponent));
    defer _ = component.vtable.release(component);
    var component_connection_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, component.vtable.queryInterface(
        component,
        &vst.ivstmessage.iconnection_point_iid,
        &component_connection_out,
    ));
    const component_connection: *vst.ivstmessage.IConnectionPoint = @ptrCast(@alignCast(component_connection_out orelse return error.MissingConnection));
    defer _ = component_connection.vtable.release(component_connection);

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Controller.create(@ptrCast(&vst.ivsteditcontroller.iedit_controller_iid), &controller_out));
    const controller: *vst.ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out orelse return error.MissingController));
    defer _ = controller.vtable.release(controller);
    var controller_connection_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, controller.vtable.queryInterface(
        controller,
        &vst.ivstmessage.iconnection_point_iid,
        &controller_connection_out,
    ));
    const controller_connection: *vst.ivstmessage.IConnectionPoint = @ptrCast(@alignCast(controller_connection_out orelse return error.MissingConnection));
    defer _ = controller_connection.vtable.release(controller_connection);
    try std.testing.expectEqual(types.kResultOk, controller_connection.vtable.connect(controller_connection, component_connection));
    defer _ = controller_connection.vtable.disconnect(controller_connection, component_connection);

    const first_view = controller.vtable.createView(controller, vst.ivsteditcontroller.ViewType.kEditor) orelse return error.MissingEditorView;
    try std.testing.expectEqual(types.kResultOk, Controller.handleFileImport(
        controller,
        sample_import_id,
        .picker,
        &.{first_path[0..first_length]},
    ));
    _ = first_view.vtable.release(first_view);
    const first_snapshot = try waitForSampleImport(controller);
    try std.testing.expectEqual(@as(usize, 64), first_snapshot.decoded_frames);
    try std.testing.expectEqualStrings("first.wav", Controller.editorState(controller).get(last_import_state_id).?.text.slice());

    try std.testing.expectEqual(types.kResultOk, Controller.handleFileImport(
        controller,
        sample_import_id,
        .drop,
        &.{replacement_path[0..replacement_length]},
    ));
    const replacement_snapshot = try waitForSampleImport(controller);
    try std.testing.expect(replacement_snapshot.import.generation > first_snapshot.import.generation);
    try std.testing.expectEqualStrings("replacement.wav", Controller.editorState(controller).get(last_import_state_id).?.text.slice());

    var processor = Effect.processorInstance(component);
    processor.prepare(.{ .sample_rate = 48_000, .max_block_size = 8 });
    var left: [8]f32 = @splat(0.0);
    var right: [8]f32 = @splat(0.0);
    const outputs = [_][]f32{ &left, &right };
    const note_on = [_]core.process.Event{core.process.Event.noteOn(0, 0, 60, 1.0)};
    var context = try core.process.ProcessContext(f32).initWith(48_000, &.{}, &outputs, .{ .events = &note_on });
    processor.process({}, f32, &context);
    try std.testing.expect(left[1] < 0.0);

    try std.testing.expectEqual(types.kResultOk, Controller.performAction(controller, clear_action_group_id, clear_action_id));
    try std.testing.expectEqualStrings("", Controller.editorState(controller).get(last_import_state_id).?.text.slice());
    left = @splat(1.0);
    right = @splat(1.0);
    var empty_context = try core.process.ProcessContext(f32).initWith(48_000, &.{}, &outputs, .{ .events = &note_on });
    processor.process({}, f32, &empty_context);
    try std.testing.expectEqualSlices(f32, &@as([8]f32, @splat(0.0)), &left);
    try std.testing.expectEqualSlices(f32, &left, &right);
}

test "sample player processor reset prevents stuck notes" {
    var processor: SamplePlayerProcessor = undefined;
    processor.initInPlace();
    processor.prepare(.{ .sample_rate = 48_000, .max_block_size = 8 });
    const receiver = processor.audioImportReceiver();
    try receiver.begin(.{ .generation = 1, .sample_rate = 48_000, .channels = 1, .frames = 8 });
    try receiver.write(1, 0, &@as([8]f32, @splat(0.5)));
    try receiver.commit(1);
    var left: [4]f32 = @splat(0.0);
    var right: [4]f32 = @splat(0.0);
    const outputs = [_][]f32{ &left, &right };
    const note_on = [_]core.process.Event{core.process.Event.noteOn(0, 0, 60, 1.0)};
    var active = try core.process.ProcessContext(f32).initWith(48_000, &.{}, &outputs, .{ .events = &note_on });
    processor.process({}, f32, &active);
    try std.testing.expect(left[1] > 0.0);
    processor.reset();
    left = @splat(1.0);
    right = @splat(1.0);
    var stopped = try core.process.ProcessContext(f32).initWith(48_000, &.{}, &outputs, .{});
    processor.process({}, f32, &stopped);
    try std.testing.expectEqualSlices(f32, &@as([4]f32, @splat(0.0)), &left);
    try std.testing.expectEqualSlices(f32, &left, &right);
}

test "sample player processor renders imported media from MIDI" {
    var processor: SamplePlayerProcessor = undefined;
    processor.initInPlace();
    processor.prepare(.{ .sample_rate = 48_000, .max_block_size = 16 });
    const receiver = processor.audioImportReceiver();
    try receiver.begin(.{ .generation = 1, .sample_rate = 48_000, .channels = 1, .frames = 4 });
    try receiver.write(1, 0, &.{ 0.0, 0.5, 1.0, 0.0 });
    try receiver.commit(1);
    var left: [4]f32 = @splat(0.0);
    var right: [4]f32 = @splat(0.0);
    const outputs = [_][]f32{ &left, &right };
    const events = [_]core.process.Event{core.process.Event.noteOn(0, 0, 60, 1.0)};
    var context = try core.process.ProcessContext(f32).initWith(48_000, &.{}, &outputs, .{ .events = &events });
    processor.process({}, f32, &context);
    try std.testing.expect(left[1] > 0.0);
    try std.testing.expectEqualSlices(f32, &left, &right);
}
