const plug = @import("zig-vst3-plugin");
const std = @import("std");

pub const VoiceCount = enum { mono, two, four, eight };
pub const PlaybackMode = enum { gate, one_shot };
pub const VoiceCountParam = plug.parameters.EnumParam(VoiceCount);
pub const PlaybackModeParam = plug.parameters.EnumParam(PlaybackMode);

pub const SamplePlayer = struct {
    pub const name = "zig-vst3 Sample Player";
    pub const vendor = "zig-vst3";
    pub const audio_input = false;

    pub const Params = struct {
        gain: plug.parameters.FloatParam = .{ .id = 0, .name = "Gain", .units = "dB", .min = -60.0, .max = 12.0, .default = 0.0 },
        pan: plug.parameters.FloatParam = .{ .id = 1, .name = "Pan", .units = "%", .min = -100.0, .max = 100.0, .default = 0.0 },
        coarse: plug.parameters.FloatParam = .{ .id = 2, .name = "Coarse", .units = "st", .min = -24.0, .max = 24.0, .default = 0.0 },
        fine: plug.parameters.FloatParam = .{ .id = 3, .name = "Fine", .units = "cent", .min = -100.0, .max = 100.0, .default = 0.0 },
        start: plug.parameters.FloatParam = .{ .id = 4, .name = "Start", .units = "%", .min = 0.0, .max = 100.0, .default = 0.0 },
        end: plug.parameters.FloatParam = .{ .id = 5, .name = "End", .units = "%", .min = 0.0, .max = 100.0, .default = 100.0 },
        loop_start: plug.parameters.FloatParam = .{ .id = 6, .name = "Loop Start", .units = "%", .min = 0.0, .max = 100.0, .default = 0.0 },
        loop_end: plug.parameters.FloatParam = .{ .id = 7, .name = "Loop End", .units = "%", .min = 0.0, .max = 100.0, .default = 100.0 },
        loop: plug.parameters.BoolParam = .{ .id = 8, .name = "Loop" },
        reverse: plug.parameters.BoolParam = .{ .id = 9, .name = "Reverse" },
        attack: plug.parameters.LogFloatParam = .{ .id = 10, .name = "Attack", .units = "ms", .min = 0.1, .max = 5_000.0, .default = 5.0 },
        decay: plug.parameters.LogFloatParam = .{ .id = 11, .name = "Decay", .units = "ms", .min = 0.1, .max = 5_000.0, .default = 80.0 },
        sustain: plug.parameters.FloatParam = .{ .id = 12, .name = "Sustain", .units = "%", .min = 0.0, .max = 100.0, .default = 80.0 },
        release: plug.parameters.LogFloatParam = .{ .id = 13, .name = "Release", .units = "ms", .min = 0.1, .max = 10_000.0, .default = 150.0 },
        voices: VoiceCountParam = .{ .id = 14, .name = "Voices", .default = .eight },
        playback: PlaybackModeParam = .{ .id = 15, .name = "Playback", .default = .gate },
    };
};

pub const Spec = plug.plugin.PluginSpec(SamplePlayer);
pub const parameter_set = Spec.ParameterSet.init(.{});

test "sample player metadata defines a bounded MIDI instrument" {
    const spec = Spec.init(.{});
    try std.testing.expectEqualStrings("zig-vst3 Sample Player", Spec.name);
    try std.testing.expectEqual(@as(usize, 16), Spec.ParameterSet.count);
    try std.testing.expect(!Spec.audio_input);
    try std.testing.expect(Spec.audio_output);
    try std.testing.expect(Spec.event_input);
    try spec.parameter_set.validate();
    try std.testing.expectEqual(@as(?f64, -100.0), parameter_set.plainMinimumById(1));
    try std.testing.expectEqual(@as(?f64, 10_000.0), parameter_set.plainMaximumById(13));
}
