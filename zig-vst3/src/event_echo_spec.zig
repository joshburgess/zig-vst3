const std = @import("std");
const plug = @import("zig-vst3-plugin-core");

pub const EventEchoPlugin = struct {
    pub const name = "zig-vst3 Event Echo";
    pub const vendor = "zig-vst3";
    pub const url = "https://github.com/joshburgess/zig-vst3";
    pub const event_output = true;
    pub const Params = struct {};

    fn processBlock(
        comptime Sample: type,
        context: *plug.process.ProcessContext(Sample),
    ) void {
        for (0..context.outputChannelCount()) |channel| {
            const input = context.inputChannel(channel) orelse continue;
            const output = context.outputChannel(channel) orelse continue;
            for (input, output) |sample, *destination| {
                destination.* = sample;
            }
        }
        _ = context.appendOutputEventsIfPossible(
            context.inputEvents(),
        );
    }

    pub fn process(
        _: *@This(),
        context: *plug.process.ProcessContext(f32),
    ) void {
        processBlock(f32, context);
    }

    pub fn process64(
        _: *@This(),
        context: *plug.process.ProcessContext(f64),
    ) void {
        processBlock(f64, context);
    }
};

pub const Spec = plug.plugin.PluginSpec(EventEchoPlugin);
pub const parameter_set = Spec.ParameterSet.init(.{});
pub const component_class_name = Spec.component_class_name;
pub const controller_class_name = Spec.controller_class_name;

fn expectInPlaceAudio(comptime Sample: type) !void {
    var samples = [_]Sample{ 0.25, -0.5, 0.75, -1.0 };
    const expected = samples;
    const input_channels = [_][]const Sample{&samples};
    const output_channels = [_][]Sample{&samples};
    var context = try plug.process.ProcessContext(Sample).init(
        48_000.0,
        &input_channels,
        &output_channels,
    );
    var plugin = EventEchoPlugin{};

    if (Sample == f32) {
        plugin.process(&context);
    } else {
        plugin.process64(&context);
    }

    try std.testing.expectEqualSlices(Sample, &expected, &samples);
}

test "event echo supports in-place 32-bit audio buffers" {
    try expectInPlaceAudio(f32);
}

test "event echo supports in-place 64-bit audio buffers" {
    try expectInPlaceAudio(f64);
}
