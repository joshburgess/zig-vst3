const std = @import("std");
const plug = @import("zig-plug");

pub const NoteGate = struct {
    pub const name = "zig-plug Core Note Gate";
    pub const vendor = "zig-vst3";
    pub const Params = struct {};

    pub fn process(_: *NoteGate, context: *plug.process.ProcessContext(f32)) void {
        const gate_open = context.events.countKind(.note_on) > 0;
        for (0..context.outputs.channels.len) |channel| {
            const input = context.inputs.channel(channel) orelse continue;
            const output = context.outputs.channel(channel) orelse continue;
            for (0..context.frameCount()) |sample| {
                output[sample] = if (gate_open) input[sample] else 0.0;
            }
        }
    }
};

pub const Spec = plug.plugin.PluginSpec(NoteGate);
pub const Instance = plug.plugin.PluginInstance(NoteGate);

test "note gate core example declares reflected metadata" {
    const spec = Spec.init(.{});

    try std.testing.expectEqualStrings("zig-plug Core Note Gate", Spec.name);
    try std.testing.expectEqualStrings("zig-vst3", Spec.vendor);
    try std.testing.expectEqual(@as(usize, 0), Spec.ParameterSet.count);
    try std.testing.expectEqual(@as(?f64, null), spec.values.load(0));
    plug.plugin.validateLifecycle(NoteGate);
}

test "note gate core example mutes without note input events" {
    var plugin = NoteGate{};
    const input = [_]f32{ 0.25, -0.5, 1.0 };
    var output = [_]f32{ 1.0, 1.0, 1.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    var context = try plug.process.ProcessContext(f32).init(48_000.0, &input_channels, &output_channels);

    plugin.process(&context);

    try std.testing.expectEqual(@as(f32, 0.0), output[0]);
    try std.testing.expectEqual(@as(f32, 0.0), output[1]);
    try std.testing.expectEqual(@as(f32, 0.0), output[2]);
}

test "note gate core example passes audio when a note-on event is present" {
    var plugin = NoteGate{};
    const input = [_]f32{ 0.25, -0.5, 1.0 };
    var output = [_]f32{ 0.0, 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const events = [_]plug.process.Event{
        plug.process.Event.noteOn(1, 0, 60, 0.75),
    };
    var context = try plug.process.ProcessContext(f32).init(48_000.0, &input_channels, &output_channels);
    try context.setEvents(&events);

    plugin.process(&context);

    try std.testing.expectEqual(@as(f32, 0.25), output[0]);
    try std.testing.expectEqual(@as(f32, -0.5), output[1]);
    try std.testing.expectEqual(@as(f32, 1.0), output[2]);
}

test "note gate core example can run through plugin instance" {
    var instance = try Instance.init(std.testing.allocator, .{});
    const input = [_]f32{ 0.25, -0.5 };
    var output = [_]f32{ 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const events = [_]plug.process.Event{
        plug.process.Event.noteOn(0, 0, 60, 0.75),
    };
    var context = try plug.process.ProcessContext(f32).init(48_000.0, &input_channels, &output_channels);
    try context.setEvents(&events);

    instance.process(&context);

    try std.testing.expectEqual(@as(f32, 0.25), output[0]);
    try std.testing.expectEqual(@as(f32, -0.5), output[1]);
}
