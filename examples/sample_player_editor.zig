const vst3 = @import("zig-vst3");

const ui = vst3.vstgui;
const gui = vst3.pluginterfaces.gui;
const types = vst3.pluginterfaces.base.types;
const vst = vst3.pluginterfaces.vst;

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
pub const zoom_state_id: u32 = 1;
pub const x_offset_state_id: u32 = 2;
pub const last_import_state_id: u32 = 3;
pub const maximum_sample_frames: usize = 262_144;
pub const maximum_voices: usize = 8;
pub const maximum_import_name_bytes: usize = 64;

pub fn createEditor(
    comptime Controller: type,
    controller: *vst.ivsteditcontroller.IEditController,
    name: types.FIDString,
    comptime default_normalized: anytype,
) ?*gui.iplugview.IPlugView {
    return ui.createEditor(Controller, controller, name, .{
        .parameters = &.{
            control(start_param_id, "Start", "%", 0, default_normalized(start_param_id), .linear_slider),
            control(end_param_id, "End", "%", 0, default_normalized(end_param_id), .linear_slider),
            control(loop_start_param_id, "Loop Start", "%", 0, default_normalized(loop_start_param_id), .linear_slider),
            control(loop_end_param_id, "Loop End", "%", 0, default_normalized(loop_end_param_id), .linear_slider),
            control(gain_param_id, "Gain", "dB", 0, default_normalized(gain_param_id), .decibel_slider),
            control(pan_param_id, "Pan", "%", 0, default_normalized(pan_param_id), .bipolar_slider),
            control(coarse_param_id, "Coarse", "st", 0, default_normalized(coarse_param_id), .rotary_knob),
            control(fine_param_id, "Fine", "cent", 0, default_normalized(fine_param_id), .rotary_knob),
            control(loop_param_id, "Loop", "", 1, default_normalized(loop_param_id), .toggle),
            control(reverse_param_id, "Reverse", "", 1, default_normalized(reverse_param_id), .toggle),
            control(playback_param_id, "Playback", "", 1, default_normalized(playback_param_id), .segmented_enum),
            control(voices_param_id, "Voices", "", 3, default_normalized(voices_param_id), .segmented_enum),
            control(attack_param_id, "Attack", "ms", 0, default_normalized(attack_param_id), .rotary_knob),
            control(decay_param_id, "Decay", "ms", 0, default_normalized(decay_param_id), .rotary_knob),
            control(sustain_param_id, "Sustain", "%", 0, default_normalized(sustain_param_id), .rotary_knob),
            control(release_param_id, "Release", "ms", 0, default_normalized(release_param_id), .rotary_knob),
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

fn control(
    id: u32,
    title: [*:0]const u8,
    units: [*:0]const u8,
    step_count: i32,
    default_normalized: f64,
    kind: @TypeOf(@as(ui.Parameter, undefined).control_kind),
) ui.Parameter {
    return .{
        .id = id,
        .title = title,
        .units = units,
        .step_count = step_count,
        .default_normalized = default_normalized,
        .control_kind = kind,
        .tooltip = tooltip(id),
    };
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
