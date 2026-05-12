const ibstream = @import("pluginterfaces/base/ibstream.zig");
const note_gate_controller = @import("note_gate_controller.zig");
const note_gate_spec = @import("note_gate_spec.zig");
const plug_process = @import("zig-vst3-plugin-core").process;
const plug_state = @import("zig-vst3-plugin-core").state;
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const vst_stream = @import("vst_stream.zig");
const zig_vst3_plugin_effect = @import("zig_vst3_plugin_effect.zig");

pub const cid = tuid.inlineUid(0x70E3A630, 0x5EE54F09, 0x94C968A8, 0x22947A9F);

const NoteGateState = struct {
    open: bool = false,
    held_notes: [128]bool = [_]bool{false} ** 128,
    held_note_count: usize = 0,

    fn process(self: *NoteGateState, comptime Sample: type, context: *plug_process.ProcessContext(Sample)) void {
        var segments = context.inputEventBlockSegments();
        while (segments.next()) |segment| {
            self.applyEventsAt(Sample, context, segment.start_offset);
            for (0..context.outputChannelCount()) |channel| {
                const input = context.inputChannel(channel) orelse continue;
                const output = context.outputChannel(channel) orelse continue;
                if (self.open) {
                    for (segment.start_offset..segment.end_offset) |sample| {
                        output[sample] = input[sample];
                    }
                } else {
                    @memset(output[segment.start_offset..segment.end_offset], 0);
                }
            }
        }
    }

    fn applyEventsAt(self: *NoteGateState, comptime Sample: type, context: *plug_process.ProcessContext(Sample), sample_offset: usize) void {
        var events = context.inputEventsAtOffset(sample_offset);
        while (events.next()) |event| {
            if (event.asNoteAttack()) |note| {
                self.holdNote(note.pitch);
            } else if (event.asNoteRelease()) |note| {
                self.releaseNote(note.pitch);
            }
        }
    }

    fn holdNote(self: *NoteGateState, pitch: i16) void {
        const index = @as(usize, @intCast(pitch));
        if (!self.held_notes[index]) {
            self.held_notes[index] = true;
            self.held_note_count += 1;
        }
        self.open = true;
    }

    fn releaseNote(self: *NoteGateState, pitch: i16) void {
        const index = @as(usize, @intCast(pitch));
        if (self.held_notes[index]) {
            self.held_notes[index] = false;
            self.held_note_count -= 1;
        }
        self.open = self.held_note_count > 0;
    }
};

var gate = NoteGateState{};

fn resetNoteGateState() void {
    gate = .{};
}

const NoteGateProcessor = struct {
    pub fn process(_: NoteGateProcessor, comptime Sample: type, context: *plug_process.ProcessContext(Sample)) void {
        gate.process(Sample, context);
    }
};

const Effect = zig_vst3_plugin_effect.SimpleStereoEffect(struct {
    pub const component_name = "NoteGateComponent";
    pub const controller_cid = note_gate_controller.cid;
    pub const Processor = NoteGateProcessor;

    pub fn resetProcessState() void {
        resetNoteGateState();
    }

    pub fn applyParameterChanges(changes: plug_process.ParameterChanges) void {
        note_gate_controller.applyParameterChanges(changes);
    }

    pub fn readState(state: ?*ibstream.IBStream) types.tresult {
        return note_gate_controller.readState(state);
    }

    pub fn writeState(state: ?*ibstream.IBStream) types.tresult {
        return note_gate_controller.writeState(state);
    }
});

pub const create = Effect.create;

test "note gate component can be created as IComponent" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");

    var out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    try std.testing.expectEqual(@as(types.int32, 1), component_iface.vtable.getBusCount(component_iface, @intFromEnum(ivstcomponent.MediaTypes.kEvent), @intFromEnum(ivstcomponent.BusDirections.kInput)));
    try std.testing.expect(component_iface.vtable.release(component_iface) >= 1);
}

test "note gate processor follows event offsets inside a block" {
    const std = @import("std");

    var local_gate = NoteGateState{};
    const input = [_]f32{ 0.25, -0.5, 1.0, -1.0 };
    var output = [_]f32{ 1.0, 1.0, 1.0, 1.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const events = [_]plug_process.Event{
        plug_process.Event.noteOn(1, 0, 60, 0.75),
        plug_process.Event.noteOff(3, 0, 60, 0.0),
    };
    var context = try plug_process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
    });

    local_gate.process(f32, &context);

    try std.testing.expectEqual(@as(f32, 0.0), output[0]);
    try std.testing.expectEqual(@as(f32, -0.5), output[1]);
    try std.testing.expectEqual(@as(f32, 1.0), output[2]);
    try std.testing.expectEqual(@as(f32, 0.0), output[3]);
    try std.testing.expect(!local_gate.open);
    try std.testing.expectEqual(@as(usize, 0), local_gate.held_note_count);
}

test "note gate component gates host event list input through processor shell" {
    const std = @import("std");
    const ivstaudioprocessor = @import("pluginterfaces/vst/ivstaudioprocessor.zig");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
    const ivstevents = @import("pluginterfaces/vst/ivstevents.zig");
    const ivstprocesscontext = @import("pluginterfaces/vst/ivstprocesscontext.zig");
    const vst_event_list = @import("vst_event_list.zig");

    resetNoteGateState();
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

    var input_samples = [_]f32{ 0.25, -0.5, 1.0, -1.0 };
    var output_samples = [_]f32{ 1.0, 1.0, 1.0, 1.0 };
    var input_channel_ptrs = [_][*]f32{&input_samples};
    var output_channel_ptrs = [_][*]f32{&output_samples};
    var inputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 1,
        .channelBuffers = .{ .channelBuffers32 = &input_channel_ptrs },
    }};
    var outputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 1,
        .channelBuffers = .{ .channelBuffers32 = &output_channel_ptrs },
    }};
    var process_context = ivstprocesscontext.ProcessContext{ .sampleRate = 48_000.0 };

    const InputEvents = vst_event_list.EventList(2);
    var input_events = InputEvents{};
    var note_on = ivstevents.Event{
        .sampleOffset = 1,
        .type = @intFromEnum(ivstevents.Event.EventTypes.kNoteOnEvent),
        .data = .{ .noteOn = .{
            .channel = 0,
            .pitch = 60,
            .velocity = 0.75,
        } },
    };
    var note_off = ivstevents.Event{
        .sampleOffset = 3,
        .type = @intFromEnum(ivstevents.Event.EventTypes.kNoteOffEvent),
        .data = .{ .noteOff = .{
            .channel = 0,
            .pitch = 60,
            .velocity = 0.0,
        } },
    };
    try std.testing.expectEqual(types.kResultOk, input_events.asInterface().vtable.addEvent(input_events.asInterface(), &note_on));
    try std.testing.expectEqual(types.kResultOk, input_events.asInterface().vtable.addEvent(input_events.asInterface(), &note_off));

    var data = ivstaudioprocessor.ProcessData{
        .numInputs = 1,
        .numOutputs = 1,
        .inputs = &inputs,
        .outputs = &outputs,
        .numSamples = 4,
        .symbolicSampleSize = @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample32),
        .inputEvents = input_events.asInterface(),
        .processContext = &process_context,
    };

    try std.testing.expectEqual(types.kResultOk, processor.vtable.process(processor, &data));
    try std.testing.expectEqualSlices(f32, &.{ 0.0, -0.5, 1.0, 0.0 }, &output_samples);
    try std.testing.expect(!gate.open);
    try std.testing.expectEqual(@as(usize, 0), gate.held_note_count);
}

test "note gate component gates host event list input through double precision processor shell" {
    const std = @import("std");
    const ivstaudioprocessor = @import("pluginterfaces/vst/ivstaudioprocessor.zig");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
    const ivstevents = @import("pluginterfaces/vst/ivstevents.zig");
    const ivstprocesscontext = @import("pluginterfaces/vst/ivstprocesscontext.zig");
    const vst_event_list = @import("vst_event_list.zig");

    resetNoteGateState();
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

    var input_samples = [_]f64{ 0.25, -0.5, 1.0, -1.0 };
    var output_samples = [_]f64{ 1.0, 1.0, 1.0, 1.0 };
    var input_channel_ptrs = [_][*]f64{&input_samples};
    var output_channel_ptrs = [_][*]f64{&output_samples};
    var inputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 1,
        .channelBuffers = .{ .channelBuffers64 = &input_channel_ptrs },
    }};
    var outputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 1,
        .channelBuffers = .{ .channelBuffers64 = &output_channel_ptrs },
    }};
    var process_context = ivstprocesscontext.ProcessContext{ .sampleRate = 48_000.0 };

    const InputEvents = vst_event_list.EventList(2);
    var input_events = InputEvents{};
    var note_on = ivstevents.Event{
        .sampleOffset = 1,
        .type = @intFromEnum(ivstevents.Event.EventTypes.kNoteOnEvent),
        .data = .{ .noteOn = .{
            .channel = 0,
            .pitch = 60,
            .velocity = 0.75,
        } },
    };
    var note_off = ivstevents.Event{
        .sampleOffset = 3,
        .type = @intFromEnum(ivstevents.Event.EventTypes.kNoteOffEvent),
        .data = .{ .noteOff = .{
            .channel = 0,
            .pitch = 60,
            .velocity = 0.0,
        } },
    };
    try std.testing.expectEqual(types.kResultOk, input_events.asInterface().vtable.addEvent(input_events.asInterface(), &note_on));
    try std.testing.expectEqual(types.kResultOk, input_events.asInterface().vtable.addEvent(input_events.asInterface(), &note_off));

    var data = ivstaudioprocessor.ProcessData{
        .numInputs = 1,
        .numOutputs = 1,
        .inputs = &inputs,
        .outputs = &outputs,
        .numSamples = 4,
        .symbolicSampleSize = @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample64),
        .inputEvents = input_events.asInterface(),
        .processContext = &process_context,
    };

    try std.testing.expectEqual(types.kResultOk, processor.vtable.process(processor, &data));
    try std.testing.expectEqualSlices(f64, &.{ 0.0, -0.5, 1.0, 0.0 }, &output_samples);
    try std.testing.expect(!gate.open);
    try std.testing.expectEqual(@as(usize, 0), gate.held_note_count);
}

test "note gate processor stays open while overlapping notes are held" {
    const std = @import("std");

    var local_gate = NoteGateState{};
    const input = [_]f32{ 0.25, -0.5, 1.0, -1.0, 0.125 };
    var output = [_]f32{ 0.0, 0.0, 0.0, 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const events = [_]plug_process.Event{
        plug_process.Event.noteOn(0, 0, 60, 0.75),
        plug_process.Event.noteOn(1, 0, 64, 0.75),
        plug_process.Event.noteOff(2, 0, 60, 0.0),
        plug_process.Event.noteOff(4, 0, 64, 0.0),
    };
    var context = try plug_process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
    });

    local_gate.process(f32, &context);

    try std.testing.expectEqual(@as(f32, 0.25), output[0]);
    try std.testing.expectEqual(@as(f32, -0.5), output[1]);
    try std.testing.expectEqual(@as(f32, 1.0), output[2]);
    try std.testing.expectEqual(@as(f32, -1.0), output[3]);
    try std.testing.expectEqual(@as(f32, 0.0), output[4]);
    try std.testing.expect(!local_gate.open);
    try std.testing.expectEqual(@as(usize, 0), local_gate.held_note_count);
}

test "note gate processor treats zero-velocity note-on as note-off" {
    const std = @import("std");

    var local_gate = NoteGateState{};
    const input = [_]f32{ 0.25, -0.5, 1.0, -1.0 };
    var output = [_]f32{ 0.0, 0.0, 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const events = [_]plug_process.Event{
        plug_process.Event.noteOn(0, 0, 60, 0.75),
        plug_process.Event.noteOn(1, 0, 64, 0.75),
        plug_process.Event.noteOn(2, 0, 60, 0.0),
        plug_process.Event.noteOn(3, 0, 64, 0.0),
    };
    var context = try plug_process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
    });

    local_gate.process(f32, &context);

    try std.testing.expectEqual(@as(f32, 0.25), output[0]);
    try std.testing.expectEqual(@as(f32, -0.5), output[1]);
    try std.testing.expectEqual(@as(f32, 1.0), output[2]);
    try std.testing.expectEqual(@as(f32, 0.0), output[3]);
    try std.testing.expect(!local_gate.open);
    try std.testing.expectEqual(@as(usize, 0), local_gate.held_note_count);
}

test "note gate component resets process state when deactivated" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");

    resetNoteGateState();
    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    const input = [_]f32{ 0.25, -0.5 };
    var output = [_]f32{ 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const events = [_]plug_process.Event{
        plug_process.Event.noteOn(0, 0, 60, 0.75),
    };
    var context = try plug_process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
    });
    (NoteGateProcessor{}).process(f32, &context);
    try std.testing.expect(gate.open);

    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.setActive(component_iface, 0));
    try std.testing.expect(!gate.open);
    try std.testing.expectEqual(@as(usize, 0), gate.held_note_count);
}

test "note gate component round-trips empty state through host callbacks" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");

    resetNoteGateState();
    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    const Stream = vst_stream.FixedBufferStream(plug_state.encodedSize(note_gate_spec.Spec.Params));
    var stream = Stream{};
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.getState(component_iface, stream.asStream()));
    try std.testing.expectEqual(@as(usize, plug_state.encoded_header_size), stream.data().len);
    try std.testing.expectEqual(types.kResultOk, stream.asStream().vtable.seek(stream.asStream(), 0, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), null));
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.setState(component_iface, stream.asStream()));
}
