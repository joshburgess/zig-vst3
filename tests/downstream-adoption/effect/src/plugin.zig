const std = @import("std");
const plug = @import("zig-vst3-plugin");
const vst3 = @import("zig-vst3");

const core = plug.core;
const vst = vst3.pluginterfaces.vst;

pub const component_cid = vst3.tuid.inlineUid(0x57B0E4A1, 0xA130416D, 0xBB84B987, 0x33C839A2);
pub const controller_cid = vst3.tuid.inlineUid(0x8CB9E501, 0x11994947, 0xA3C6E453, 0x5BA0CF82);
pub const preset_bytes = @embedFile("assets/default-preset.txt");

const Definition = struct {
    pub const name = "Downstream Saturator";
    pub const vendor = "Downstream Fixture";
    pub const url = "https://example.invalid/downstream-effect";
    pub const audio_input_layout: core.plugin.AudioBusLayout = .stereo;
    pub const audio_output_layout: core.plugin.AudioBusLayout = .stereo;
    pub const Params = struct {
        drive: core.parameters.FloatParam = .{ .id = 10, .name = "Drive", .units = "dB", .min = 0.0, .max = 24.0, .default = 0.0 },
        mix: core.parameters.FloatParam = .{ .id = 20, .name = "Mix", .units = "%", .min = 0.0, .max = 100.0, .default = 100.0 },
    };

    prepared_sample_rate: f64 = 0.0,
    restore_count: usize = 0,

    pub fn prepare(self: *@This(), config: core.plugin.PrepareConfig) void {
        self.prepared_sample_rate = config.sample_rate;
    }

    pub fn processWithParameterView(
        _: *@This(),
        context: *core.process.ProcessContext(f32),
        parameters: core.parameters.ParameterView(Params),
    ) void {
        const drive = @as(f32, @floatCast(parameters.load("drive") / 24.0));
        const mix = @as(f32, @floatCast(parameters.load("mix") / 100.0));
        for (0..context.outputChannelCount()) |channel| {
            const input = context.inputChannel(channel) orelse continue;
            const output = context.outputChannel(channel) orelse continue;
            for (input, output) |sample, *destination| {
                const saturated = std.math.tanh(sample * (1.0 + drive * 3.0));
                destination.* = sample + (saturated - sample) * mix;
            }
        }
    }

    pub fn afterStateRestore(self: *@This()) void {
        self.restore_count += 1;
    }
};

pub const Spec = core.plugin.PluginSpec(Definition);
pub const Instance = core.plugin.PluginInstance(Definition);
pub const parameter_set = Spec.ParameterSet.init(.{});

const Effect = plug.Vst3Effect(Definition, struct {
    pub const component_name = "DownstreamEffectComponent";
    pub const controller_cid = @import("plugin.zig").controller_cid;
});
const Controller = plug.Vst3Controller(Definition, "DownstreamEffectController");
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

test "downstream effect runs lifecycle, automation, resources, and state migration" {
    var instance = try Instance.init(std.testing.allocator, .{});
    try instance.prepareChecked(.{ .sample_rate = 48_000.0, .max_block_size = 4 });
    try std.testing.expectEqual(@as(f64, 48_000.0), instance.plugin.prepared_sample_rate);
    try std.testing.expectEqualStrings("drive=0.25\nmix=0.75\n", preset_bytes);
    const identity = core.resource.Identity.fromBytes(preset_bytes);
    try std.testing.expectEqual(@as(u64, preset_bytes.len), identity.byte_length);

    const input = [_]f32{ -0.5, 0.25, 0.75, -1.0 };
    var left_output = [_]f32{0.0} ** input.len;
    var right_output = [_]f32{0.0} ** input.len;
    const inputs = [_][]const f32{ &input, &input };
    const outputs = [_][]f32{ &left_output, &right_output };
    const changes = [_]core.process.ParameterChange{
        parameter_set.parameterChange("drive", 0, 12.0),
        parameter_set.parameterChange("mix", 0, 50.0),
    };
    var context = try core.process.ProcessContext(f32).initWith(48_000.0, &inputs, &outputs, .{ .parameter_changes = &changes });
    instance.process(&context);
    try std.testing.expect(left_output[0] < 0.0);
    try std.testing.expect(left_output[2] > 0.0);

    const LegacyParams = struct {
        amount: core.parameters.FloatParam = .{ .id = 1, .name = "Amount", .min = 0.0, .max = 1.0, .default = 0.0 },
        mix: core.parameters.FloatParam = .{ .id = 20, .name = "Mix", .min = 0.0, .max = 100.0, .default = 100.0 },
    };
    const LegacySet = core.parameters.ParameterSet(LegacyParams);
    const LegacyValues = core.parameters.ParameterValues(LegacyParams);
    const legacy_set = LegacySet.init(.{});
    var legacy_values = LegacyValues.init(&legacy_set);
    try std.testing.expect(legacy_values.storeField(&legacy_set, "amount", 0.5));
    try std.testing.expect(legacy_values.storeField(&legacy_set, "mix", 75.0));
    var encoded: [core.state.encodedSize(LegacyParams)]u8 = undefined;
    var writer = std.Io.Writer.fixed(&encoded);
    try core.state.writeParameterState(LegacyParams, &legacy_set, &legacy_values, &writer);

    var reader = std.Io.Reader.fixed(writer.buffered());
    const report = try instance.readParameterStateWithMigrationsReport(&reader, &.{.{ .old_id = 1, .new_id = 10 }});
    instance.afterStateRestore();
    try std.testing.expect(report.restoredAllEntries());
    try std.testing.expectEqual(@as(f64, 0.5), instance.parameterValuesConst().loadById(&parameter_set, 10).?);
    try std.testing.expectEqual(@as(f64, 0.75), instance.parameterValuesConst().loadById(&parameter_set, 20).?);
    try std.testing.expectEqual(@as(usize, 1), instance.plugin.restore_count);
}

test "downstream effect class identifiers and installed imports remain stable" {
    try std.testing.expectEqualStrings("0.3.0-rc.1", plug.version);
    try std.testing.expectEqual(component_cid, vst3.tuid.inlineUid(0x57B0E4A1, 0xA130416D, 0xBB84B987, 0x33C839A2));
    try std.testing.expectEqual(controller_cid, vst3.tuid.inlineUid(0x8CB9E501, 0x11994947, 0xA3C6E453, 0x5BA0CF82));
    try std.testing.expect(@hasDecl(vst.ivstaudioprocessor, "IAudioProcessor"));
}
