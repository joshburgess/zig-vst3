const std = @import("std");
const plug = @import("zig-plug");

pub const SineSynth = struct {
    pub const name = "zig-plug Core Sine Synth";
    pub const vendor = "zig-vst3";
    pub const Params = struct {
        level: plug.parameters.FloatParam = .{ .id = 0, .name = "Level", .short_name = "Level", .min = 0.0, .max = 1.0, .default = 0.1 },
    };

    active: bool = false,
    note: i16 = 69,
    phase: f64 = 0.0,

    pub fn process(self: *SineSynth, context: *plug.process.ProcessContext(f32)) void {
        context.clearOutputs();

        var segments = context.processBlockSegments();
        while (segments.next()) |segment| {
            self.applyEventsAt(context, segment.start_offset);
            if (!self.active) continue;
            const level = @as(f32, @floatCast(context.parameterNormalizedAtOrBeforeOr(0, segment.start_offset, 0.1)));
            const frequency = midiFrequency(self.note);
            const step = frequency / context.sample_rate;
            for (segment.start_offset..segment.end_offset) |sample| {
                const value = @as(f32, @floatCast(std.math.sin(self.phase * std.math.tau))) * level;
                for (0..context.outputChannelCount()) |channel| {
                    const output = context.outputChannel(channel) orelse continue;
                    output[sample] = value;
                }
                self.phase += step;
                if (self.phase >= 1.0) self.phase -= @floor(self.phase);
            }
        }
    }

    fn applyEventsAt(self: *SineSynth, context: *plug.process.ProcessContext(f32), sample_offset: usize) void {
        var events = context.inputEventsAtOffset(sample_offset);
        while (events.next()) |event| {
            if (event.asNoteOn()) |note| {
                if (note.velocity > 0.0) {
                    self.active = true;
                    self.note = note.pitch;
                    self.phase = 0.0;
                } else if (note.pitch == self.note) {
                    self.active = false;
                }
            } else if (event.asNoteOff()) |note| {
                if (note.pitch == self.note) self.active = false;
            }
        }
    }

    fn midiFrequency(note: i16) f64 {
        return 440.0 * std.math.pow(f64, 2.0, (@as(f64, @floatFromInt(note)) - 69.0) / 12.0);
    }
};

pub const Spec = plug.plugin.PluginSpec(SineSynth);
pub const Instance = plug.plugin.PluginInstance(SineSynth);
pub const parameter_set = Spec.ParameterSet.init(.{});

test "sine synth core example declares reflected metadata" {
    const spec = Spec.init(.{});

    try std.testing.expectEqualStrings("zig-plug Core Sine Synth", Spec.name);
    try std.testing.expectEqualStrings("zig-vst3", Spec.vendor);
    try std.testing.expectEqual(@as(usize, 1), Spec.ParameterSet.count);
    try std.testing.expectEqual(@as(usize, 1), parameter_set.parameterCount());
    try std.testing.expectEqualStrings("Level", parameter_set.name(0).?);
    try std.testing.expectEqual(@as(f64, 0.1), spec.values.view(&parameter_set).loadNormalized("level"));
    plug.plugin.validateLifecycle(SineSynth);
}

test "sine synth core example responds to note events inside a block" {
    var plugin = SineSynth{};
    var output = [_]f32{ 1.0, 1.0, 1.0, 1.0, 1.0 };
    const input_channels = [_][]const f32{};
    const output_channels = [_][]f32{&output};
    const events = [_]plug.process.Event{
        plug.process.Event.noteOn(1, 0, 69, 1.0),
        plug.process.Event.noteOff(4, 0, 69, 0.0),
    };
    var context = try plug.process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
    });

    try std.testing.expectEqual(@as(usize, 0), context.inputFrameCount());
    try std.testing.expectEqual(@as(usize, output.len), context.outputFrameCount());
    try std.testing.expectEqual(@as(usize, output.len), context.frameCount());

    plugin.process(&context);

    try std.testing.expectEqual(@as(f32, 0.0), output[0]);
    try std.testing.expectEqual(@as(f32, 0.0), output[1]);
    try std.testing.expect(output[2] > 0.0);
    try std.testing.expect(output[3] > output[2]);
    try std.testing.expectEqual(@as(f32, 0.0), output[4]);
    try std.testing.expect(!plugin.active);
}

test "sine synth core example applies level automation at segment boundaries" {
    var plugin = SineSynth{};
    var output = [_]f32{ 0.0, 0.0, 0.0, 0.0 };
    const input_channels = [_][]const f32{};
    const output_channels = [_][]f32{&output};
    const events = [_]plug.process.Event{
        plug.process.Event.noteOn(0, 0, 69, 1.0),
    };
    const changes = [_]plug.process.ParameterChange{
        parameter_set.parameterChange("level", 2, 0.0),
    };
    var context = try plug.process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
        .parameter_changes = &changes,
    });

    plugin.process(&context);

    try std.testing.expectEqual(@as(f32, 0.0), output[0]);
    try std.testing.expect(output[1] > 0.0);
    try std.testing.expectEqual(@as(f32, 0.0), output[2]);
    try std.testing.expectEqual(@as(f32, 0.0), output[3]);
    try std.testing.expect(plugin.active);
}

test "sine synth core example treats zero-velocity note-on as note-off" {
    var plugin = SineSynth{};
    var output = [_]f32{ 0.0, 0.0, 0.0, 0.0 };
    const input_channels = [_][]const f32{};
    const output_channels = [_][]f32{&output};
    const events = [_]plug.process.Event{
        plug.process.Event.noteOn(0, 0, 69, 1.0),
        plug.process.Event.noteOn(2, 0, 69, 0.0),
    };
    var context = try plug.process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
    });

    plugin.process(&context);

    try std.testing.expectEqual(@as(f32, 0.0), output[0]);
    try std.testing.expect(output[1] > 0.0);
    try std.testing.expectEqual(@as(f32, 0.0), output[2]);
    try std.testing.expectEqual(@as(f32, 0.0), output[3]);
    try std.testing.expect(!plugin.active);
    try std.testing.expectEqual(@as(i16, 69), plugin.note);
}

test "sine synth core example can run through plugin instance" {
    var instance = try Instance.init(std.testing.allocator, .{});
    const input = [_]f32{ 0.0, 0.0, 0.0 };
    var output = [_]f32{ 0.0, 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const events = [_]plug.process.Event{
        plug.process.Event.noteOn(0, 0, 69, 1.0),
    };
    var context = try plug.process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
    });

    instance.process(&context);

    try std.testing.expect(instance.plugin.active);
    try std.testing.expect(output[1] > 0.0);
    try std.testing.expect(output[2] > output[1]);
}
