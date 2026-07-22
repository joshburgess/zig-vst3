const core = @import("zig-vst3-plugin-core");
const std = @import("std");
const vst3 = @import("zig-vst3");

const base = vst3.pluginterfaces.base;
const vst = vst3.pluginterfaces.vst;
const types = base.types;

const Definition = struct {
    pub const name = "zig-vst3 Mono Gain";
    pub const vendor = "zig-vst3";
    pub const url = "https://github.com/joshburgess/zig-vst3";
    pub const audio_input_layout: core.plugin.AudioBusLayout = .mono;
    pub const audio_output_layout: core.plugin.AudioBusLayout = .mono;
    pub const Params = struct {
        gain: core.parameters.FloatParam = .{
            .id = 0,
            .name = "Gain",
            .min = 0.0,
            .max = 2.0,
            .default = 1.0,
        },
    };
};

pub const Spec = core.plugin.PluginSpec(Definition);
const mono_parameter_set = Spec.ParameterSet.init(.{});

pub const component_cid = vst3.tuid.inlineUid(0x9DFB88F1, 0x2D1C47EF, 0xA6DF8CE4, 0x6A8B3C11);
pub const mono_controller_cid = vst3.tuid.inlineUid(0xE7B36D20, 0xC4F8405D, 0x9C1A5D92, 0x803FC7A4);

const MonoProcessor = struct {
    pub fn process(_: *MonoProcessor, parameters: anytype, comptime Sample: type, context: *core.process.ProcessContext(Sample)) void {
        const input = context.inputChannel(0) orelse return;
        const output = context.outputChannel(0) orelse return;
        const gain: Sample = @floatCast(parameters.getNormalizedById(0) * 2.0);
        for (input, output) |sample, *destination| destination.* = sample * gain;
    }
};

const Effect = vst3.zig_vst3_plugin_effect.SimpleEffect(struct {
    pub const component_name = "MonoGainComponent";
    pub const controller_cid = mono_controller_cid;
    pub const audio_input_layout = Spec.audio_input_layout;
    pub const audio_output_layout = Spec.audio_output_layout;
    pub const Params = Spec.Params;
    pub const parameter_set = &mono_parameter_set;
    pub const Processor = MonoProcessor;
});

const Controller = vst3.zig_vst3_plugin_effect.ReflectedEditController(struct {
    pub const controller_name = "MonoGainController";
    pub const Params = Spec.Params;
    pub const parameter_set = &mono_parameter_set;
});

const Factory = vst3.factory.StaticFactory3(.{
    .vendor = Spec.vendor,
    .url = Spec.url,
    .email = Spec.email,
}, &.{
    .{ .cid = component_cid, .category = Spec.component_category, .name = Spec.component_class_name, .create = Effect.create },
    .{ .cid = mono_controller_cid, .category = Spec.controller_category, .name = Spec.controller_class_name, .create = Controller.create },
});

comptime {
    vst3.entry.exportPlugin(Factory);
}

test "mono gain exposes mono buses and arrangements" {
    var component_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Effect.create(@ptrCast(&vst.ivstcomponent.icomponent_iid), &component_out));
    const component: *vst.ivstcomponent.IComponent = @ptrCast(@alignCast(component_out.?));
    defer _ = component.vtable.release(component);

    var info: vst.ivstcomponent.BusInfo = .{};
    try std.testing.expectEqual(types.kResultOk, component.vtable.getBusInfo(component, @intFromEnum(vst.ivstcomponent.MediaTypes.kAudio), @intFromEnum(vst.ivstcomponent.BusDirections.kInput), 0, &info));
    try std.testing.expectEqual(@as(types.int32, 1), info.channelCount);

    var processor_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, component.vtable.queryInterface(component, &vst.ivstaudioprocessor.iaudio_processor_iid, &processor_out));
    const processor: *vst.ivstaudioprocessor.IAudioProcessor = @ptrCast(@alignCast(processor_out.?));
    defer _ = processor.vtable.release(processor);

    var inputs = [_]vst.vsttypes.SpeakerArrangement{vst.vstspeaker.SpeakerArr.kMono};
    var outputs = [_]vst.vsttypes.SpeakerArrangement{vst.vstspeaker.SpeakerArr.kMono};
    try std.testing.expectEqual(types.kResultOk, processor.vtable.setBusArrangements(processor, &inputs, 1, &outputs, 1));
    inputs[0] = vst.vstspeaker.SpeakerArr.kStereo;
    try std.testing.expectEqual(types.kResultFalse, processor.vtable.setBusArrangements(processor, &inputs, 1, &outputs, 1));
}
