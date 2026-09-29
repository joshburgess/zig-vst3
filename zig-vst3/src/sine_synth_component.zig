const ibstream = @import("pluginterfaces/base/ibstream.zig");
const plug_process = @import("zig-vst3-plugin-core").process;
const plug_state = @import("zig-vst3-plugin-core").state;
const sine_synth_controller = @import("sine_synth_controller.zig");
const sine_synth_spec = @import("sine_synth_spec.zig");
const std = @import("std");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const vst_stream = @import("vst_stream.zig");
const zig_vst3_plugin_effect = @import("zig_vst3_plugin_effect.zig");
const plug_core = @import("zig-vst3-plugin-core");

pub const cid = tuid.inlineUid(0x8C7F6A10, 0x4D2B4A9F, 0xA515C8A1, 0xBC1E3D72);

const SineSynthState = struct {
    active: bool = false,
    note: i16 = 69,
    phase: f64 = 0.0,
    sample_position: u64 = 0,

    fn process(self: *SineSynthState, default_level: f64, comptime Sample: type, context: *plug_process.ProcessContext(Sample)) void {
        self.processSequenced(default_level, @splat(1.0), Sample, context);
    }

    fn processSequenced(
        self: *SineSynthState,
        default_level: f64,
        default_steps: [sine_synth_spec.step_param_ids.len]f64,
        comptime Sample: type,
        context: *plug_process.ProcessContext(Sample),
    ) void {
        context.clearOutputs();

        var segments = context.processBlockSegments();
        while (segments.next()) |segment| {
            self.applyEventsAt(Sample, context, segment.start_offset);
            const level: Sample = @floatCast(context.parameterNormalizedAtOrBeforeOr(
                sine_synth_controller.level_param_id,
                segment.start_offset,
                default_level,
            ));
            const step = midiFrequency(self.note) / context.sample_rate;
            for (segment.start_offset..segment.end_offset) |sample| {
                const sequence_step: usize = @intCast((self.sample_position / 6_000) % sine_synth_spec.step_param_ids.len);
                const step_active = context.parameterNormalizedAtOrBeforeOr(
                    sine_synth_spec.step_param_ids[sequence_step],
                    sample,
                    default_steps[sequence_step],
                ) >= 0.5;
                if (self.active and step_active) {
                    const value: Sample = @floatCast(std.math.sin(self.phase * std.math.tau) * @as(f64, @floatCast(level)));
                    for (0..context.outputChannelCount()) |channel| {
                        const output = context.outputChannel(channel) orelse continue;
                        output[sample] = value;
                    }
                }
                if (self.active) {
                    self.phase += step;
                    if (self.phase >= 1.0) self.phase -= @floor(self.phase);
                }
                self.sample_position +%= 1;
            }
        }
    }

    fn applyEventsAt(self: *SineSynthState, comptime Sample: type, context: *plug_process.ProcessContext(Sample), sample_offset: usize) void {
        var events = context.inputEventsAtOffset(sample_offset);
        while (events.next()) |event| {
            if (event.asNoteAttack()) |note| {
                self.active = true;
                self.note = note.pitch;
                self.phase = 0.0;
            } else if (event.asNoteRelease()) |note| {
                if (note.pitch == self.note) self.active = false;
            }
        }
    }

    fn midiFrequency(note: i16) f64 {
        return 440.0 * std.math.pow(f64, 2.0, (@as(f64, @floatFromInt(note)) - 69.0) / 12.0);
    }
};

const SineSynthProcessor = struct {
    const Telemetry = plug_core.gui_telemetry.MeterBank(f64, 1);

    state: SineSynthState = .{},
    telemetry: Telemetry = Telemetry.init(-1.0),

    pub fn reset(self: *SineSynthProcessor) void {
        self.state = .{};
    }

    pub fn process(self: *SineSynthProcessor, parameters: anytype, comptime Sample: type, context: *plug_process.ProcessContext(Sample)) void {
        var steps: [sine_synth_spec.step_param_ids.len]f64 = undefined;
        for (&steps, sine_synth_spec.step_param_ids) |*value, parameter_id| {
            value.* = parameters.getNormalizedById(parameter_id);
        }
        self.state.processSequenced(
            parameters.getNormalizedById(sine_synth_controller.level_param_id),
            steps,
            Sample,
            context,
        );
        if (self.telemetry.producing()) {
            _ = self.telemetry.publish(0, @floatFromInt((self.state.sample_position / 6_000) % steps.len));
        }
    }

    pub fn guiTelemetryLoad(self: *SineSynthProcessor, source_id: types.uint32) f64 {
        if (source_id != 0x100) return -1.0;
        return self.telemetry.load(0) orelse -1.0;
    }

    pub fn guiTelemetryEditorOpened(self: *SineSynthProcessor) void {
        self.telemetry.editorOpened();
    }

    pub fn guiTelemetryEditorClosed(self: *SineSynthProcessor) void {
        self.telemetry.editorClosed();
    }
};

const Effect = zig_vst3_plugin_effect.SimpleStereoEffect(struct {
    pub const component_name = "SineSynthComponent";
    pub const controller_cid = sine_synth_controller.cid;
    pub const event_input = sine_synth_spec.Spec.event_input;
    pub const gui_note_input = true;
    pub const audio_input = sine_synth_spec.Spec.audio_input;
    pub const Params = sine_synth_spec.Spec.Params;
    pub const parameter_set = &sine_synth_spec.parameter_set;
    pub const Processor = SineSynthProcessor;
});

pub const create = Effect.create;

test "sine synth component can be created as IComponent" {
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");

    var out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    try std.testing.expectEqual(@as(types.int32, 0), component_iface.vtable.getBusCount(component_iface, @intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kInput)));
    try std.testing.expectEqual(@as(types.int32, 1), component_iface.vtable.getBusCount(component_iface, @intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kOutput)));
    try std.testing.expectEqual(@as(types.int32, 1), component_iface.vtable.getBusCount(component_iface, @intFromEnum(ivstcomponent.MediaTypes.kEvent), @intFromEnum(ivstcomponent.BusDirections.kInput)));
    try std.testing.expectEqual(@as(types.uint32, 0), component_iface.vtable.release(component_iface));
}

test "sine synth processor responds to note events and level automation" {
    var local_synth = SineSynthState{};
    var output = [_]f32{ 0.0, 0.0, 0.0, 0.0 };
    const input_channels = [_][]const f32{};
    const output_channels = [_][]f32{&output};
    const events = [_]plug_process.Event{
        plug_process.Event.noteOn(0, 0, 69, 1.0),
    };
    const changes = [_]plug_process.ParameterChange{
        .{ .id = sine_synth_controller.level_param_id, .sample_offset = 2, .normalized = 0.0 },
    };
    var context = try plug_process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
        .parameter_changes = &changes,
    });

    local_synth.process(1.0, f32, &context);

    try std.testing.expectEqual(@as(f32, 0.0), output[0]);
    try std.testing.expect(output[1] > 0.0);
    try std.testing.expectEqual(@as(f32, 0.0), output[2]);
    try std.testing.expectEqual(@as(f32, 0.0), output[3]);
    try std.testing.expect(local_synth.active);
}

test "sine synth sequencer gates audio without changing transport progress" {
    var local_synth = SineSynthState{};
    var output = [_]f32{ 1.0, 1.0, 1.0, 1.0 };
    const input_channels = [_][]const f32{};
    const output_channels = [_][]f32{&output};
    const events = [_]plug_process.Event{plug_process.Event.noteOn(0, 0, 69, 1.0)};
    var context = try plug_process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
    });
    var steps: [sine_synth_spec.step_param_ids.len]f64 = @splat(1.0);
    steps[0] = 0.0;

    local_synth.processSequenced(1.0, steps, f32, &context);

    try std.testing.expectEqualSlices(f32, &.{ 0.0, 0.0, 0.0, 0.0 }, &output);
    try std.testing.expectEqual(@as(u64, output.len), local_synth.sample_position);
    try std.testing.expect(local_synth.phase > 0.0);
}

test "sine synth playhead telemetry is editor activity gated" {
    var processor = SineSynthProcessor{};
    try std.testing.expectEqual(@as(f64, -1.0), processor.guiTelemetryLoad(0x100));
    processor.guiTelemetryEditorOpened();
    defer processor.guiTelemetryEditorClosed();
    try std.testing.expect(processor.telemetry.publish(0, 3.0));
    try std.testing.expectEqual(@as(f64, 3.0), processor.guiTelemetryLoad(0x100));
    try std.testing.expectEqual(@as(f64, -1.0), processor.guiTelemetryLoad(0x101));
}

test "sine synth component renders host event list input through processor shell" {
    const ivstaudioprocessor = @import("pluginterfaces/vst/ivstaudioprocessor.zig");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
    const ivstevents = @import("pluginterfaces/vst/ivstevents.zig");
    const ivstprocesscontext = @import("pluginterfaces/vst/ivstprocesscontext.zig");
    const vst_event_list = @import("vst_event_list.zig");
    const vst_parameter_changes = @import("vst_parameter_changes.zig");

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    var processor_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component_iface.vtable.queryInterface(component_iface, &ivstaudioprocessor.iaudio_processor_iid, &processor_out),
    );
    try std.testing.expect(processor_out != null);
    const processor: *ivstaudioprocessor.IAudioProcessor = @ptrCast(@alignCast(processor_out.?));
    defer _ = processor.vtable.release(processor);

    var left = [_]f32{ 1.0, 1.0, 1.0, 1.0 };
    var right = [_]f32{ 1.0, 1.0, 1.0, 1.0 };
    var output_channel_ptrs = [_][*]f32{ &left, &right };
    var outputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 2,
        .channelBuffers = .{ .channelBuffers32 = output_channel_ptrs[0..].ptr },
    }};
    var process_context = ivstprocesscontext.ProcessContext{ .sampleRate = 48_000.0 };

    const InputEvents = vst_event_list.EventList(2);
    var input_events = InputEvents{};
    var note_on = ivstevents.Event{
        .sampleOffset = 0,
        .type = @intFromEnum(ivstevents.Event.EventTypes.kNoteOnEvent),
        .data = .{ .noteOn = .{
            .channel = 0,
            .pitch = 69,
            .velocity = 1.0,
        } },
    };
    var note_off = ivstevents.Event{
        .sampleOffset = 3,
        .type = @intFromEnum(ivstevents.Event.EventTypes.kNoteOffEvent),
        .data = .{ .noteOff = .{
            .channel = 0,
            .pitch = 69,
            .velocity = 0.0,
        } },
    };
    try std.testing.expectEqual(types.kResultOk, input_events.asInterface().vtable.addEvent(input_events.asInterface(), &note_on));
    try std.testing.expectEqual(types.kResultOk, input_events.asInterface().vtable.addEvent(input_events.asInterface(), &note_off));

    const Changes = vst_parameter_changes.ParameterChanges(1, 1);
    var changes = Changes{};
    const level_queue = changes.addQueue(sine_synth_controller.level_param_id).?;
    try std.testing.expectEqual(types.kResultOk, level_queue.appendPoint(0, 1.0));

    var data = ivstaudioprocessor.ProcessData{
        .numInputs = 0,
        .numOutputs = 1,
        .outputs = &outputs,
        .numSamples = 4,
        .symbolicSampleSize = @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample32),
        .inputEvents = input_events.asInterface(),
        .inputParameterChanges = changes.asInterface(),
        .processContext = &process_context,
    };

    try std.testing.expectEqual(types.kResultOk, processor.vtable.process(processor, &data));
    try std.testing.expectEqual(@as(f32, 0.0), left[0]);
    try std.testing.expect(left[1] > 0.0);
    try std.testing.expect(left[2] > left[1]);
    try std.testing.expectEqual(@as(f32, 0.0), left[3]);
    try std.testing.expectEqualSlices(f32, &left, &right);
    try std.testing.expect(!Effect.processorInstance(component_iface).state.active);
    try std.testing.expectEqual(@as(f64, 1.0), Effect.getParameterNormalized(component_iface, sine_synth_controller.level_param_id));
}

test "sine synth component renders GUI note mailbox input" {
    const gui_note_transport = @import("gui_note_transport.zig");
    const ivstaudioprocessor = @import("pluginterfaces/vst/ivstaudioprocessor.zig");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
    const ivstmessage = @import("pluginterfaces/vst/ivstmessage.zig");
    const ivstprocesscontext = @import("pluginterfaces/vst/ivstprocesscontext.zig");

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out orelse return error.MissingComponent));
    defer _ = component_iface.vtable.release(component_iface);

    var processor_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component_iface.vtable.queryInterface(component_iface, &ivstaudioprocessor.iaudio_processor_iid, &processor_out),
    );
    const processor: *ivstaudioprocessor.IAudioProcessor = @ptrCast(@alignCast(processor_out orelse return error.MissingProcessor));
    defer _ = processor.vtable.release(processor);
    var connection_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component_iface.vtable.queryInterface(component_iface, &ivstmessage.iconnection_point_iid, &connection_out),
    );
    const connection: *ivstmessage.IConnectionPoint = @ptrCast(@alignCast(connection_out orelse return error.MissingConnection));
    defer _ = connection.vtable.release(connection);

    var left = [_]f32{ 0.0, 0.0, 0.0, 0.0 };
    var right = left;
    var output_channel_ptrs = [_][*]f32{ &left, &right };
    var outputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 2,
        .channelBuffers = .{ .channelBuffers32 = output_channel_ptrs[0..].ptr },
    }};
    var process_context = ivstprocesscontext.ProcessContext{ .sampleRate = 48_000.0 };
    var data = ivstaudioprocessor.ProcessData{
        .numInputs = 0,
        .numOutputs = 1,
        .outputs = &outputs,
        .numSamples = left.len,
        .symbolicSampleSize = @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample32),
        .processContext = &process_context,
    };

    try std.testing.expectEqual(types.kResultOk, gui_note_transport.send(connection, .{
        .pitch = 69,
        .velocity = 1.0,
        .pressed = true,
    }));
    try std.testing.expectEqual(types.kResultOk, processor.vtable.process(processor, &data));
    try std.testing.expect(left[1] > 0.0);
    try std.testing.expect(Effect.processorInstance(component_iface).state.active);

    try std.testing.expectEqual(types.kResultOk, gui_note_transport.send(connection, .{
        .pitch = 69,
        .velocity = 0.0,
        .pressed = false,
    }));
    @memset(left[0..], 1.0);
    @memset(right[0..], 1.0);
    try std.testing.expectEqual(types.kResultOk, processor.vtable.process(processor, &data));
    try std.testing.expectEqualSlices(f32, &.{ 0.0, 0.0, 0.0, 0.0 }, &left);
    try std.testing.expect(!Effect.processorInstance(component_iface).state.active);
}

test "sine synth component renders host event list input through double precision processor shell" {
    const ivstaudioprocessor = @import("pluginterfaces/vst/ivstaudioprocessor.zig");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
    const ivstevents = @import("pluginterfaces/vst/ivstevents.zig");
    const ivstprocesscontext = @import("pluginterfaces/vst/ivstprocesscontext.zig");
    const vst_event_list = @import("vst_event_list.zig");
    const vst_parameter_changes = @import("vst_parameter_changes.zig");

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    var processor_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component_iface.vtable.queryInterface(component_iface, &ivstaudioprocessor.iaudio_processor_iid, &processor_out),
    );
    try std.testing.expect(processor_out != null);
    const processor: *ivstaudioprocessor.IAudioProcessor = @ptrCast(@alignCast(processor_out.?));
    defer _ = processor.vtable.release(processor);

    var left = [_]f64{ 1.0, 1.0, 1.0, 1.0 };
    var right = [_]f64{ 1.0, 1.0, 1.0, 1.0 };
    var output_channel_ptrs = [_][*]f64{ &left, &right };
    var outputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 2,
        .channelBuffers = .{ .channelBuffers64 = output_channel_ptrs[0..].ptr },
    }};
    var process_context = ivstprocesscontext.ProcessContext{ .sampleRate = 48_000.0 };

    const InputEvents = vst_event_list.EventList(2);
    var input_events = InputEvents{};
    var note_on = ivstevents.Event{
        .sampleOffset = 0,
        .type = @intFromEnum(ivstevents.Event.EventTypes.kNoteOnEvent),
        .data = .{ .noteOn = .{
            .channel = 0,
            .pitch = 69,
            .velocity = 1.0,
        } },
    };
    var note_off = ivstevents.Event{
        .sampleOffset = 3,
        .type = @intFromEnum(ivstevents.Event.EventTypes.kNoteOffEvent),
        .data = .{ .noteOff = .{
            .channel = 0,
            .pitch = 69,
            .velocity = 0.0,
        } },
    };
    try std.testing.expectEqual(types.kResultOk, input_events.asInterface().vtable.addEvent(input_events.asInterface(), &note_on));
    try std.testing.expectEqual(types.kResultOk, input_events.asInterface().vtable.addEvent(input_events.asInterface(), &note_off));

    const Changes = vst_parameter_changes.ParameterChanges(1, 1);
    var changes = Changes{};
    const level_queue = changes.addQueue(sine_synth_controller.level_param_id).?;
    try std.testing.expectEqual(types.kResultOk, level_queue.appendPoint(0, 1.0));

    var data = ivstaudioprocessor.ProcessData{
        .numInputs = 0,
        .numOutputs = 1,
        .outputs = &outputs,
        .numSamples = 4,
        .symbolicSampleSize = @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample64),
        .inputEvents = input_events.asInterface(),
        .inputParameterChanges = changes.asInterface(),
        .processContext = &process_context,
    };

    try std.testing.expectEqual(types.kResultOk, processor.vtable.process(processor, &data));
    try std.testing.expectEqual(@as(f64, 0.0), left[0]);
    try std.testing.expect(left[1] > 0.0);
    try std.testing.expect(left[2] > left[1]);
    try std.testing.expectEqual(@as(f64, 0.0), left[3]);
    try std.testing.expectEqualSlices(f64, &left, &right);
    try std.testing.expect(!Effect.processorInstance(component_iface).state.active);
    try std.testing.expectEqual(@as(f64, 1.0), Effect.getParameterNormalized(component_iface, sine_synth_controller.level_param_id));
}

test "sine synth processor treats zero-velocity note-on as note-off" {
    var local_synth = SineSynthState{};
    var output = [_]f32{ 0.0, 0.0, 0.0, 0.0 };
    const input_channels = [_][]const f32{};
    const output_channels = [_][]f32{&output};
    const events = [_]plug_process.Event{
        plug_process.Event.noteOn(0, 0, 69, 1.0),
        plug_process.Event.noteOn(2, 0, 69, 0.0),
    };
    var context = try plug_process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
    });

    local_synth.process(1.0, f32, &context);

    try std.testing.expectEqual(@as(f32, 0.0), output[0]);
    try std.testing.expect(output[1] > 0.0);
    try std.testing.expectEqual(@as(f32, 0.0), output[2]);
    try std.testing.expectEqual(@as(f32, 0.0), output[3]);
    try std.testing.expect(!local_synth.active);
}

test "sine synth component uses spec default level" {
    try std.testing.expectEqual(@as(f64, 0.1), sine_synth_spec.default_level);
}

test "sine synth component resets process state when deactivated" {
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    var output = [_]f32{ 0.0, 0.0 };
    const input_channels = [_][]const f32{};
    const output_channels = [_][]f32{&output};
    const events = [_]plug_process.Event{
        plug_process.Event.noteOn(0, 0, 69, 1.0),
    };
    var context = try plug_process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
    });
    Effect.processorInstance(component_iface).state.process(1.0, f32, &context);
    try std.testing.expect(Effect.processorInstance(component_iface).state.active);

    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.setActive(component_iface, 0));
    try std.testing.expect(!Effect.processorInstance(component_iface).state.active);
    try std.testing.expectEqual(@as(i16, 69), Effect.processorInstance(component_iface).state.note);
    try std.testing.expectEqual(@as(f64, 0.0), Effect.processorInstance(component_iface).state.phase);
}

test "sine synth component round-trips level state through host callbacks" {
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);
    try std.testing.expectEqual(types.kResultOk, Effect.setParameterNormalized(component_iface, sine_synth_controller.level_param_id, 0.75));

    const Stream = vst_stream.FixedBufferStream(plug_state.encodedSize(sine_synth_spec.Spec.Params));
    var stream = Stream{};
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.getState(component_iface, stream.asStream()));
    try std.testing.expectEqual(@as(usize, plug_state.encodedSize(sine_synth_spec.Spec.Params)), stream.data().len);

    try std.testing.expectEqual(types.kResultOk, Effect.setParameterNormalized(component_iface, sine_synth_controller.level_param_id, 0.0));
    try std.testing.expectEqual(@as(f64, 0.0), Effect.getParameterNormalized(component_iface, sine_synth_controller.level_param_id));
    try std.testing.expectEqual(types.kResultOk, stream.asStream().vtable.seek(stream.asStream(), 0, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), null));
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.setState(component_iface, stream.asStream()));
    try std.testing.expectApproxEqAbs(@as(f64, 0.75), Effect.getParameterNormalized(component_iface, sine_synth_controller.level_param_id), 0.000001);
}
