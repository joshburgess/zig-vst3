const std = @import("std");
const plug = @import("zig-plug");

pub const EventEcho = struct {
    pub const name = "zig-plug Core Event Echo";
    pub const vendor = "zig-vst3";
    pub const Params = struct {};

    pub fn process(_: *EventEcho, context: *plug.process.ProcessContext(f32)) void {
        const events = context.inputEvents();
        if (!context.canAppendOutputEvents(events.eventCount())) return;
        context.appendOutputEvents(events) catch unreachable;
    }
};

pub const Spec = plug.plugin.PluginSpec(EventEcho);
pub const Instance = plug.plugin.PluginInstance(EventEcho);

test "event echo core example declares reflected metadata" {
    try std.testing.expectEqualStrings("zig-plug Core Event Echo", Spec.name);
    try std.testing.expectEqualStrings("zig-vst3", Spec.vendor);
    try std.testing.expectEqual(@as(usize, 0), Spec.ParameterSet.count);
    plug.plugin.validateLifecycle(EventEcho);
}

test "event echo core example writes input events to output events" {
    var plugin = EventEcho{};
    const input = [_]f32{ 0.0, 0.0 };
    var output = [_]f32{ 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const events = [_]plug.process.Event{
        plug.process.Event.noteOn(1, 0, 60, 0.75),
    };
    var output_event_storage: [1]plug.process.Event = undefined;
    var output_events = plug.process.EventWriter.init(&output_event_storage, input.len);
    var context = try plug.process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
        .output_events = &output_events,
    });

    plugin.process(&context);

    try std.testing.expectEqual(@as(usize, 1), context.outputEventCount());
    try std.testing.expectEqual(@as(usize, 0), context.outputEventRemainingCapacity());
    try std.testing.expect(context.hasOutputEvent(.note_on));
    try std.testing.expectEqual(@as(usize, 1), context.countOutputEvents(.note_on));
    try std.testing.expectEqual(@as(usize, 1), context.firstOutputEvent(.note_on).?.sample_offset);
    try std.testing.expectEqual(@as(usize, 1), context.firstOutputEventOffset().?);
}

test "event echo core example leaves output unchanged when capacity is too small" {
    var plugin = EventEcho{};
    const input = [_]f32{ 0.0, 0.0 };
    var output = [_]f32{ 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const events = [_]plug.process.Event{
        plug.process.Event.noteOn(0, 0, 60, 0.75),
        plug.process.Event.noteOff(1, 0, 60, 0.0),
    };
    var output_event_storage: [1]plug.process.Event = undefined;
    var output_events = plug.process.EventWriter.init(&output_event_storage, input.len);
    var context = try plug.process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
        .output_events = &output_events,
    });

    plugin.process(&context);

    try std.testing.expectEqual(@as(usize, 0), context.outputEventCount());
    try std.testing.expectEqual(@as(usize, 1), context.outputEventRemainingCapacity());
}

test "event echo core example can run through plugin instance" {
    var instance = try Instance.init(std.testing.allocator, .{});
    const input = [_]f32{0.0};
    var output = [_]f32{0.0};
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const events = [_]plug.process.Event{
        plug.process.Event.noteOff(0, 0, 60, 0.0),
    };
    var output_event_storage: [1]plug.process.Event = undefined;
    var output_events = plug.process.EventWriter.init(&output_event_storage, input.len);
    var context = try plug.process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
        .output_events = &output_events,
    });

    instance.process(&context);

    try std.testing.expectEqual(@as(usize, 1), context.outputEventCount());
    try std.testing.expect(context.hasOutputEvent(.note_off));
    try std.testing.expectEqual(@as(usize, 0), context.firstOutputEvent(.note_off).?.sample_offset);
}
