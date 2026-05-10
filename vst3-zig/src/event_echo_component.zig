const event_echo_controller = @import("event_echo_controller.zig");
const event_echo_spec = @import("event_echo_spec.zig");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const plug_process = @import("zig-plug-core").process;
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const zig_plug_effect = @import("zig_plug_effect.zig");

pub const cid = tuid.inlineUid(0xD9C97C5A, 0x062A4B52, 0x9C3DF51C, 0xFFAC4B41);

const EventEchoProcessor = struct {
    pub fn process(_: EventEchoProcessor, comptime Sample: type, context: *plug_process.ProcessContext(Sample)) void {
        for (0..context.outputChannelCount()) |channel| {
            const input = context.inputChannel(channel) orelse continue;
            const output = context.outputChannel(channel) orelse continue;
            for (0..context.frameCount()) |sample| {
                output[sample] = input[sample];
            }
        }

        context.appendOutputEvents(context.inputEvents()) catch {};
    }
};

const Effect = zig_plug_effect.SimpleStereoEffect(struct {
    pub const component_name = "EventEchoComponent";
    pub const controller_cid = event_echo_controller.cid;
    pub const event_output = event_echo_spec.Spec.event_output;
    pub const Processor = EventEchoProcessor;

    pub fn applyParameterChanges(changes: plug_process.ParameterChanges) void {
        event_echo_controller.applyParameterChanges(changes);
    }

    pub fn readState(state: ?*ibstream.IBStream) types.tresult {
        return event_echo_controller.readState(state);
    }

    pub fn writeState(state: ?*ibstream.IBStream) types.tresult {
        return event_echo_controller.writeState(state);
    }
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
    try std.testing.expect(component_iface.vtable.release(component_iface) >= 1);
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

    const processor = EventEchoProcessor{};
    processor.process(f32, &context);

    try std.testing.expectEqualSlices(f32, &input, &output);
    try std.testing.expectEqual(@as(usize, 1), context.outputEventCount());
    try std.testing.expect(context.hasOutputEvent(.note_on));
    try std.testing.expectEqual(@as(usize, 1), context.firstOutputEvent(.note_on).?.sample_offset);
}
