const event_echo_controller = @import("event_echo_controller.zig");
const event_echo_spec = @import("event_echo_spec.zig");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const plug_process = @import("zig-vst3-plugin-core").process;
const plug_state = @import("zig-vst3-plugin-core").state;
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const vst_stream = @import("vst_stream.zig");
const zig_vst3_plugin_effect = @import("zig_vst3_plugin_effect.zig");

pub const cid = tuid.inlineUid(0xD9C97C5A, 0x062A4B52, 0x9C3DF51C, 0xFFAC4B41);

const EventEchoProcessor = struct {
    pub fn process(_: *EventEchoProcessor, _: anytype, comptime Sample: type, context: *plug_process.ProcessContext(Sample)) void {
        for (0..context.outputChannelCount()) |channel| {
            const input = context.inputChannel(channel) orelse continue;
            const output = context.outputChannel(channel) orelse continue;
            for (0..context.frameCount()) |sample| {
                output[sample] = input[sample];
            }
        }

        _ = context.appendOutputEventsIfPossible(context.inputEvents());
    }
};

const Effect = zig_vst3_plugin_effect.SimpleStereoEffect(struct {
    pub const component_name = "EventEchoComponent";
    pub const controller_cid = event_echo_controller.cid;
    pub const event_output = event_echo_spec.Spec.event_output;
    pub const Params = event_echo_spec.Spec.Params;
    pub const parameter_set = &event_echo_spec.parameter_set;
    pub const Processor = EventEchoProcessor;
});

pub const create = Effect.create;

test "event echo component can be created with input and output event buses" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");

    var out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    try std.testing.expectEqual(@as(types.int32, 1), component_iface.vtable.getBusCount(component_iface, @intFromEnum(ivstcomponent.MediaTypes.kEvent), @intFromEnum(ivstcomponent.BusDirections.kInput)));
    try std.testing.expectEqual(@as(types.int32, 1), component_iface.vtable.getBusCount(component_iface, @intFromEnum(ivstcomponent.MediaTypes.kEvent), @intFromEnum(ivstcomponent.BusDirections.kOutput)));
    try std.testing.expectEqual(@as(types.uint32, 0), component_iface.vtable.release(component_iface));
}

test "event echo processor copies audio and input events" {
    const std = @import("std");

    const input = [_]f32{ 0.25, -0.5 };
    var output = [_]f32{ 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const events = [_]plug_process.Event{
        plug_process.Event.noteOn(1, 0, 60, 0.75),
    };
    var output_event_storage: [1]plug_process.Event = undefined;
    var output_events = plug_process.EventWriter.init(&output_event_storage, input.len);
    var context = try plug_process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
        .output_events = &output_events,
    });

    var processor = EventEchoProcessor{};
    processor.process(&.{}, f32, &context);

    try std.testing.expectEqualSlices(f32, &input, &output);
    try std.testing.expectEqual(@as(usize, 1), context.outputEventCount());
    try std.testing.expect(context.hasOutputEvent(.note_on));
    try std.testing.expectEqual(@as(usize, 1), context.firstOutputEvent(.note_on).?.sample_offset);
}

test "event echo component writes output events through processor shell" {
    const std = @import("std");
    const ivstaudioprocessor = @import("pluginterfaces/vst/ivstaudioprocessor.zig");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
    const ivstevents = @import("pluginterfaces/vst/ivstevents.zig");
    const ivstprocesscontext = @import("pluginterfaces/vst/ivstprocesscontext.zig");
    const vst_event_list = @import("vst_event_list.zig");

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

    var input_samples = [_]f32{ 0.25, -0.5 };
    var output_samples = [_]f32{ 0.0, 0.0 };
    var input_channel_ptrs = [_][*]f32{&input_samples};
    var output_channel_ptrs = [_][*]f32{&output_samples};
    var inputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 1,
        .channelBuffers = .{ .channelBuffers32 = input_channel_ptrs[0..].ptr },
    }};
    var outputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 1,
        .channelBuffers = .{ .channelBuffers32 = output_channel_ptrs[0..].ptr },
    }};
    var process_context = ivstprocesscontext.ProcessContext{ .sampleRate = 48_000.0 };

    const InputEvents = vst_event_list.EventList(1);
    var input_events = InputEvents{};
    var input_event = ivstevents.Event{
        .sampleOffset = 1,
        .type = @intFromEnum(ivstevents.Event.EventTypes.kNoteOnEvent),
        .data = .{ .noteOn = .{
            .channel = 0,
            .pitch = 60,
            .velocity = 0.75,
        } },
    };
    try std.testing.expectEqual(types.kResultOk, input_events.asInterface().vtable.addEvent(input_events.asInterface(), &input_event));

    const OutputEvents = vst_event_list.EventList(1);
    var output_events = OutputEvents{};
    var data = ivstaudioprocessor.ProcessData{
        .numInputs = 1,
        .numOutputs = 1,
        .inputs = &inputs,
        .outputs = &outputs,
        .numSamples = 2,
        .symbolicSampleSize = @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample32),
        .inputEvents = input_events.asInterface(),
        .outputEvents = output_events.asInterface(),
        .processContext = &process_context,
    };

    try std.testing.expectEqual(types.kResultOk, processor.vtable.process(processor, &data));
    try std.testing.expectEqualSlices(f32, &input_samples, &output_samples);
    try std.testing.expectEqual(@as(types.int32, 1), output_events.asInterface().vtable.getEventCount(output_events.asInterface()));

    var written_event = ivstevents.Event{};
    try std.testing.expectEqual(types.kResultOk, output_events.asInterface().vtable.getEvent(output_events.asInterface(), 0, &written_event));
    try std.testing.expectEqual(@intFromEnum(ivstevents.Event.EventTypes.kNoteOnEvent), written_event.type);
    try std.testing.expectEqual(@as(types.int32, 0), written_event.busIndex);
    try std.testing.expectEqual(@as(types.int32, 1), written_event.sampleOffset);
    try std.testing.expectEqual(@as(types.int16, 0), written_event.data.noteOn.channel);
    try std.testing.expectEqual(@as(types.int16, 60), written_event.data.noteOn.pitch);
    try std.testing.expectEqual(@as(f32, 0.75), written_event.data.noteOn.velocity);
}

test "event echo component writes output events through double precision processor shell" {
    const std = @import("std");
    const ivstaudioprocessor = @import("pluginterfaces/vst/ivstaudioprocessor.zig");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
    const ivstevents = @import("pluginterfaces/vst/ivstevents.zig");
    const ivstprocesscontext = @import("pluginterfaces/vst/ivstprocesscontext.zig");
    const vst_event_list = @import("vst_event_list.zig");

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

    var input_samples = [_]f64{ 0.25, -0.5 };
    var output_samples = [_]f64{ 0.0, 0.0 };
    var input_channel_ptrs = [_][*]f64{&input_samples};
    var output_channel_ptrs = [_][*]f64{&output_samples};
    var inputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 1,
        .channelBuffers = .{ .channelBuffers64 = input_channel_ptrs[0..].ptr },
    }};
    var outputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 1,
        .channelBuffers = .{ .channelBuffers64 = output_channel_ptrs[0..].ptr },
    }};
    var process_context = ivstprocesscontext.ProcessContext{ .sampleRate = 48_000.0 };

    const InputEvents = vst_event_list.EventList(1);
    var input_events = InputEvents{};
    var input_event = ivstevents.Event{
        .sampleOffset = 1,
        .type = @intFromEnum(ivstevents.Event.EventTypes.kNoteOnEvent),
        .data = .{ .noteOn = .{
            .channel = 0,
            .pitch = 60,
            .velocity = 0.75,
        } },
    };
    try std.testing.expectEqual(types.kResultOk, input_events.asInterface().vtable.addEvent(input_events.asInterface(), &input_event));

    const OutputEvents = vst_event_list.EventList(1);
    var output_events = OutputEvents{};
    var data = ivstaudioprocessor.ProcessData{
        .numInputs = 1,
        .numOutputs = 1,
        .inputs = &inputs,
        .outputs = &outputs,
        .numSamples = 2,
        .symbolicSampleSize = @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample64),
        .inputEvents = input_events.asInterface(),
        .outputEvents = output_events.asInterface(),
        .processContext = &process_context,
    };

    try std.testing.expectEqual(types.kResultOk, processor.vtable.process(processor, &data));
    try std.testing.expectEqualSlices(f64, &input_samples, &output_samples);
    try std.testing.expectEqual(@as(types.int32, 1), output_events.asInterface().vtable.getEventCount(output_events.asInterface()));

    var written_event = ivstevents.Event{};
    try std.testing.expectEqual(types.kResultOk, output_events.asInterface().vtable.getEvent(output_events.asInterface(), 0, &written_event));
    try std.testing.expectEqual(@intFromEnum(ivstevents.Event.EventTypes.kNoteOnEvent), written_event.type);
    try std.testing.expectEqual(@as(types.int32, 0), written_event.busIndex);
    try std.testing.expectEqual(@as(types.int32, 1), written_event.sampleOffset);
    try std.testing.expectEqual(@as(types.int16, 0), written_event.data.noteOn.channel);
    try std.testing.expectEqual(@as(types.int16, 60), written_event.data.noteOn.pitch);
    try std.testing.expectEqual(@as(f32, 0.75), written_event.data.noteOn.velocity);
}

test "event echo component round-trips empty state through host callbacks" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    const Stream = vst_stream.FixedBufferStream(plug_state.encodedSize(event_echo_spec.Spec.Params));
    var stream = Stream{};
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.getState(component_iface, stream.asStream()));
    try std.testing.expectEqual(@as(usize, plug_state.encoded_header_size), stream.data().len);
    try std.testing.expectEqual(types.kResultOk, stream.asStream().vtable.seek(stream.asStream(), 0, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), null));
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.setState(component_iface, stream.asStream()));
}
