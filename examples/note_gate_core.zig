const std = @import("std");
const plug = @import("zig-plug");

pub const NoteGate = struct {
    pub const name = "zig-plug Core Note Gate";
    pub const vendor = "zig-vst3";
    pub const Params = struct {};

    open: bool = false,
    held_notes: [16][128]bool = [_][128]bool{[_]bool{false} ** 128} ** 16,
    held_note_count: usize = 0,

    pub fn process(self: *NoteGate, context: *plug.process.ProcessContext(f32)) void {
        var segments = context.inputEventBlockSegments();
        while (segments.next()) |segment| {
            self.applyEventsAt(context, segment.start_offset);
            for (0..context.outputChannelCount()) |channel| {
                const input = context.inputChannel(channel) orelse continue;
                const output = context.outputChannel(channel) orelse continue;
                if (self.open) {
                    for (segment.start_offset..segment.end_offset) |sample| {
                        output[sample] = input[sample];
                    }
                } else {
                    @memset(output[segment.start_offset..segment.end_offset], 0.0);
                }
            }
        }
    }

    fn applyEventsAt(self: *NoteGate, context: *plug.process.ProcessContext(f32), sample_offset: usize) void {
        var events = context.inputEventsAtOffset(sample_offset);
        while (events.next()) |event| {
            if (event.asNoteAttack()) |note| {
                self.holdNote(note.channel, note.pitch);
            } else if (event.asNoteRelease()) |note| {
                self.releaseNote(note.channel, note.pitch);
            }
        }
    }

    fn holdNote(self: *NoteGate, channel: i16, pitch: i16) void {
        const channel_index = @as(usize, @intCast(channel));
        const pitch_index = @as(usize, @intCast(pitch));
        if (!self.held_notes[channel_index][pitch_index]) {
            self.held_notes[channel_index][pitch_index] = true;
            self.held_note_count += 1;
        }
        self.open = true;
    }

    fn releaseNote(self: *NoteGate, channel: i16, pitch: i16) void {
        const channel_index = @as(usize, @intCast(channel));
        const pitch_index = @as(usize, @intCast(pitch));
        if (self.held_notes[channel_index][pitch_index]) {
            self.held_notes[channel_index][pitch_index] = false;
            self.held_note_count -= 1;
        }
        self.open = self.held_note_count > 0;
    }
};

pub const Spec = plug.plugin.PluginSpec(NoteGate);
pub const Instance = plug.plugin.PluginInstance(NoteGate);

test "note gate core example declares reflected metadata" {
    try std.testing.expectEqualStrings("zig-plug Core Note Gate", Spec.name);
    try std.testing.expectEqualStrings("zig-vst3", Spec.vendor);
    try std.testing.expectEqual(@as(usize, 0), Spec.ParameterSet.count);
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
    var context = try plug.process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
    });

    plugin.process(&context);

    try std.testing.expectEqual(@as(f32, 0.0), output[0]);
    try std.testing.expectEqual(@as(f32, -0.5), output[1]);
    try std.testing.expectEqual(@as(f32, 1.0), output[2]);
    try std.testing.expect(plugin.open);
}

test "note gate core example closes on note-off inside a block" {
    var plugin = NoteGate{};
    const input = [_]f32{ 0.25, -0.5, 1.0, -1.0 };
    var output = [_]f32{ 1.0, 1.0, 1.0, 1.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const events = [_]plug.process.Event{
        plug.process.Event.noteOn(1, 0, 60, 0.75),
        plug.process.Event.noteOff(3, 0, 60, 0.0),
    };
    var context = try plug.process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
    });

    plugin.process(&context);

    try std.testing.expectEqual(@as(f32, 0.0), output[0]);
    try std.testing.expectEqual(@as(f32, -0.5), output[1]);
    try std.testing.expectEqual(@as(f32, 1.0), output[2]);
    try std.testing.expectEqual(@as(f32, 0.0), output[3]);
    try std.testing.expect(!plugin.open);
    try std.testing.expectEqual(@as(usize, 0), plugin.held_note_count);
}

test "note gate core example stays open while overlapping notes are held" {
    var plugin = NoteGate{};
    const input = [_]f32{ 0.25, -0.5, 1.0, -1.0, 0.125 };
    var output = [_]f32{ 0.0, 0.0, 0.0, 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const events = [_]plug.process.Event{
        plug.process.Event.noteOn(0, 0, 60, 0.75),
        plug.process.Event.noteOn(1, 0, 64, 0.75),
        plug.process.Event.noteOff(2, 0, 60, 0.0),
        plug.process.Event.noteOff(4, 0, 64, 0.0),
    };
    var context = try plug.process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
    });

    plugin.process(&context);

    try std.testing.expectEqual(@as(f32, 0.25), output[0]);
    try std.testing.expectEqual(@as(f32, -0.5), output[1]);
    try std.testing.expectEqual(@as(f32, 1.0), output[2]);
    try std.testing.expectEqual(@as(f32, -1.0), output[3]);
    try std.testing.expectEqual(@as(f32, 0.0), output[4]);
    try std.testing.expect(!plugin.open);
    try std.testing.expectEqual(@as(usize, 0), plugin.held_note_count);
}

test "note gate core example tracks same pitch on separate channels" {
    var plugin = NoteGate{};
    const input = [_]f32{ 0.25, -0.5, 1.0, -1.0, 0.125 };
    var output = [_]f32{ 0.0, 0.0, 0.0, 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const events = [_]plug.process.Event{
        plug.process.Event.noteOn(0, 0, 60, 0.75),
        plug.process.Event.noteOn(1, 1, 60, 0.75),
        plug.process.Event.noteOff(2, 0, 60, 0.0),
        plug.process.Event.noteOff(4, 1, 60, 0.0),
    };
    var context = try plug.process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
    });

    plugin.process(&context);

    try std.testing.expectEqual(@as(f32, 0.25), output[0]);
    try std.testing.expectEqual(@as(f32, -0.5), output[1]);
    try std.testing.expectEqual(@as(f32, 1.0), output[2]);
    try std.testing.expectEqual(@as(f32, -1.0), output[3]);
    try std.testing.expectEqual(@as(f32, 0.0), output[4]);
    try std.testing.expect(!plugin.open);
    try std.testing.expectEqual(@as(usize, 0), plugin.held_note_count);
}

test "note gate core example treats zero-velocity note-on as note-off for that pitch" {
    var plugin = NoteGate{};
    const input = [_]f32{ 0.25, -0.5, 1.0, -1.0 };
    var output = [_]f32{ 0.0, 0.0, 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const events = [_]plug.process.Event{
        plug.process.Event.noteOn(0, 0, 60, 0.75),
        plug.process.Event.noteOn(1, 0, 64, 0.75),
        plug.process.Event.noteOn(2, 0, 60, 0.0),
        plug.process.Event.noteOn(3, 0, 64, 0.0),
    };
    var context = try plug.process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
    });

    plugin.process(&context);

    try std.testing.expectEqual(@as(f32, 0.25), output[0]);
    try std.testing.expectEqual(@as(f32, -0.5), output[1]);
    try std.testing.expectEqual(@as(f32, 1.0), output[2]);
    try std.testing.expectEqual(@as(f32, 0.0), output[3]);
    try std.testing.expect(!plugin.open);
    try std.testing.expectEqual(@as(usize, 0), plugin.held_note_count);
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
    var context = try plug.process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
    });

    instance.process(&context);

    try std.testing.expectEqual(@as(f32, 0.25), output[0]);
    try std.testing.expectEqual(@as(f32, -0.5), output[1]);
    try std.testing.expect(instance.plugin.open);
    try std.testing.expectEqual(@as(usize, 1), instance.plugin.held_note_count);
}
