const std = @import("std");
const plug = @import("zig-vst3-plugin");
const vst3 = @import("zig-vst3");

const core = plug.core;

pub const component_cid = vst3.tuid.inlineUid(0x01C857D2, 0x1E8B4146, 0x99F55EA8, 0xC71F9531);
pub const controller_cid = vst3.tuid.inlineUid(0x2970CF42, 0xA4F34A7B, 0xBF5BBD40, 0x2A87A56F);
pub const wavetable_bytes = @embedFile("assets/wavetable.txt");

const Definition = struct {
    pub const name = "Downstream Instrument";
    pub const vendor = "Downstream Fixture";
    pub const audio_input = false;
    pub const Params = struct {
        level: core.parameters.FloatParam = .{ .id = 100, .name = "Level", .min = 0.0, .max = 1.0, .default = 0.2 },
    };

    active: bool = false,
    phase: f64 = 0.0,

    pub fn process(self: *@This(), context: *core.process.ProcessContext(f32)) void {
        context.clearOutputs();
        var segments = context.processBlockSegments();
        while (segments.next()) |segment| {
            var events = context.inputEventsAtOffset(segment.start_offset);
            while (events.next()) |event| {
                if (event.asNoteAttack()) |_| self.active = true;
                if (event.asNoteRelease()) |_| self.active = false;
            }
            if (!self.active) continue;
            const level = @as(f32, @floatCast(context.parameterNormalizedAtOrBeforeOr(100, segment.start_offset, 0.2)));
            for (segment.start_offset..segment.end_offset) |frame| {
                const sample = @as(f32, @floatCast(std.math.sin(self.phase * std.math.tau))) * level;
                for (0..context.outputChannelCount()) |channel| {
                    const output = context.outputChannel(channel) orelse continue;
                    output[frame] = sample;
                }
                self.phase += 440.0 / context.sampleRate();
                if (self.phase >= 1.0) self.phase -= 1.0;
            }
        }
    }
};

pub const Spec = core.plugin.PluginSpec(Definition);
pub const Instance = core.plugin.PluginInstance(Definition);
pub const parameter_set = Spec.ParameterSet.init(.{});

const Effect = plug.Vst3Effect(Definition, struct {
    pub const component_name = "DownstreamInstrumentComponent";
    pub const controller_cid = @import("plugin.zig").controller_cid;
});
const Controller = plug.Vst3Controller(Definition, "DownstreamInstrumentController");
const Factory = vst3.factory.StaticFactory3(.{
    .vendor = Spec.vendor,
    .url = Spec.url,
    .email = Spec.email,
}, &.{
    .{ .cid = component_cid, .category = Spec.component_category, .name = Spec.component_class_name, .create = Effect.create },
    .{ .cid = controller_cid, .category = Spec.controller_category, .name = Spec.controller_class_name, .create = Controller.create },
});

comptime {
    vst3.entry.exportPlugin(Factory);
}

test "downstream instrument handles events, automation, state, and resources" {
    var instance = try Instance.init(std.testing.allocator, .{});
    try std.testing.expectEqualStrings("0.0 1.0 0.0 -1.0\n", wavetable_bytes);
    const identity = core.resource.Identity.fromBytes(wavetable_bytes);
    try std.testing.expectEqual(@as(u64, wavetable_bytes.len), identity.byte_length);

    var output = [_]f32{0.0} ** 6;
    const inputs = [_][]const f32{};
    const outputs = [_][]f32{&output};
    const events = [_]core.process.Event{
        core.process.Event.noteOn(0, 0, 69, 1.0),
        core.process.Event.noteOff(5, 0, 69, 0.0),
    };
    const changes = [_]core.process.ParameterChange{
        parameter_set.parameterChange("level", 2, 0.75),
    };
    var context = try core.process.ProcessContext(f32).initWith(48_000.0, &inputs, &outputs, .{
        .events = &events,
        .parameter_changes = &changes,
    });
    instance.process(&context);
    try std.testing.expect(output[1] > 0.0);
    try std.testing.expect(output[3] > output[2]);
    try std.testing.expectEqual(@as(f32, 0.0), output[5]);
    try std.testing.expect(!instance.plugin.active);

    try std.testing.expect(instance.parameterValues().storeField(&parameter_set, "level", 0.6));
    var encoded: [Spec.encoded_parameter_state_size]u8 = undefined;
    var writer = std.Io.Writer.fixed(&encoded);
    try instance.writeParameterState(&writer);
    try std.testing.expect(instance.parameterValues().storeField(&parameter_set, "level", 0.1));
    var reader = std.Io.Reader.fixed(writer.buffered());
    try instance.readParameterState(&reader);
    try std.testing.expectEqual(@as(f64, 0.6), instance.parameterValuesConst().loadField(&parameter_set, "level"));
}

test "downstream instrument class identifiers and package version remain stable" {
    try std.testing.expectEqualStrings("0.3.0", plug.version);
    try std.testing.expectEqual(component_cid, vst3.tuid.inlineUid(0x01C857D2, 0x1E8B4146, 0x99F55EA8, 0xC71F9531));
    try std.testing.expectEqual(controller_cid, vst3.tuid.inlineUid(0x2970CF42, 0xA4F34A7B, 0xBF5BBD40, 0x2A87A56F));
}
