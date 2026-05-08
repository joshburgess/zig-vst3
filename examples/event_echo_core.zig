const std = @import("std");
const plug = @import("zig-plug");

pub const EventEcho = struct {
    pub const name = "zig-plug Core Event Echo";
    pub const vendor = "zig-vst3";
    pub const Params = struct {};

    pub fn process(_: *EventEcho, context: *plug.process.ProcessContext(f32)) void {
        const writer = context.output_events orelse return;
        for (context.events.items) |event| {
            writer.append(event) catch {};
        }
    }
};

pub const Spec = plug.plugin.PluginSpec(EventEcho);
pub const Instance = plug.plugin.PluginInstance(EventEcho);

test "event echo core example declares reflected metadata" {
    const spec = Spec.init(.{});

    try std.testing.expectEqualStrings("zig-plug Core Event Echo", Spec.name);
    try std.testing.expectEqualStrings("zig-vst3", Spec.vendor);
    try std.testing.expectEqual(@as(usize, 0), Spec.ParameterSet.count);
    try std.testing.expectEqual(@as(?f64, null), spec.values.load(0));
    plug.plugin.validateLifecycle(EventEcho);
}

test "event echo core example writes input events to output events" {
    var plugin = EventEcho{};
    const input = [_]f32{ 0.0, 0.0 };
    var output = [_]f32{ 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const events = [_]plug.process.Event{
        .{ .kind = .note_on, .bus_index = 0, .sample_offset = 1, .channel = 0, .pitch = 60, .velocity = 0.75 },
    };
    var output_event_storage: [1]plug.process.Event = undefined;
    var output_events = plug.process.EventWriter.init(&output_event_storage, input.len);
    var context = try plug.process.ProcessContext(f32).init(48_000.0, &input_channels, &output_channels);
    context.events = try plug.process.Events.init(&events, input.len);
    context.output_events = &output_events;

    plugin.process(&context);

    try std.testing.expectEqual(@as(usize, 1), output_events.events().items.len);
    try std.testing.expectEqual(plug.process.EventKind.note_on, output_events.events().items[0].kind);
    try std.testing.expectEqual(@as(usize, 1), output_events.events().items[0].sample_offset);
}

test "event echo core example can run through plugin instance" {
    var instance = try Instance.init(std.testing.allocator, .{});
    const input = [_]f32{0.0};
    var output = [_]f32{0.0};
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const events = [_]plug.process.Event{
        .{ .kind = .note_off, .bus_index = 0, .sample_offset = 0, .channel = 0, .pitch = 60, .velocity = 0.0 },
    };
    var output_event_storage: [1]plug.process.Event = undefined;
    var output_events = plug.process.EventWriter.init(&output_event_storage, input.len);
    var context = try plug.process.ProcessContext(f32).init(48_000.0, &input_channels, &output_channels);
    context.events = try plug.process.Events.init(&events, input.len);
    context.output_events = &output_events;

    instance.process(&context);

    try std.testing.expectEqual(@as(usize, 1), output_events.events().items.len);
    try std.testing.expectEqual(plug.process.EventKind.note_off, output_events.events().items[0].kind);
}
