const core = @import("zig-vst3-plugin-core");
const std = @import("std");
const vst3 = @import("zig-vst3");

const vst = vst3.pluginterfaces.vst;

extern fn installed_dense_dot4(weights: [*]const f32, input: [*]const f32) callconv(.c) f32;

const Definition = struct {
    pub const name = "Installed C Kernel";
    pub const vendor = "Example Audio";
    pub const audio_input_layout: core.plugin.AudioBusLayout = .mono;
    pub const audio_output_layout: core.plugin.AudioBusLayout = .mono;
    pub const event_input = false;
    pub const Params = struct {};
};

const Spec = core.plugin.PluginSpec(Definition);
const installed_parameter_set = Spec.ParameterSet.init(.{});
const installed_controller_cid = vst3.tuid.inlineUid(0x5A1E73B6, 0x86D64CBE, 0xAA1FC875, 0x215427B4);
const installed_component_cid = vst3.tuid.inlineUid(0x0CD97F6A, 0x2F4D4BC0, 0x8CF153A6, 0x584E3058);

const InstalledProcessor = struct {
    pub fn process(_: *InstalledProcessor, _: anytype, comptime Sample: type, context: *core.process.ProcessContext(Sample)) void {
        const input = context.inputChannel(0) orelse return;
        const output = context.outputChannel(0) orelse return;
        if (Sample != f32) {
            @memcpy(output, input);
            return;
        }
        const weights = [4]f32{ 1, 0, 0, 0 };
        for (input, output) |sample, *destination| {
            const features = [4]f32{ sample, 0, 0, 0 };
            destination.* = installed_dense_dot4(&weights, &features);
        }
    }
};

const Effect = vst3.zig_vst3_plugin_effect.SimpleEffect(struct {
    pub const component_name = "InstalledCKernelComponent";
    pub const controller_cid = installed_controller_cid;
    pub const dynamic_audio_bus_topology = Spec.dynamic_audio_bus_topology;
    pub const audio_input_layout = Spec.audio_input_layout;
    pub const audio_output_layout = Spec.audio_output_layout;
    pub const event_input = false;
    pub const Params = Spec.Params;
    pub const parameter_set = &installed_parameter_set;
    pub const Processor = InstalledProcessor;
});

const Controller = vst3.zig_vst3_plugin_effect.ReflectedEditController(struct {
    pub const controller_name = "InstalledCKernelController";
    pub const Params = Spec.Params;
    pub const parameter_set = &installed_parameter_set;
});

const Factory = vst3.factory.StaticFactory3(.{
    .vendor = Spec.vendor,
    .url = Spec.url,
    .email = Spec.email,
}, &.{
    .{ .cid = installed_component_cid, .category = Spec.component_category, .name = Spec.component_class_name, .create = Effect.create },
    .{ .cid = installed_controller_cid, .category = Spec.controller_category, .name = Spec.controller_class_name, .create = Controller.create },
});

comptime {
    vst3.entry.exportPlugin(Factory);
}

test "installed consumer links caller-owned buffers through C" {
    const weights = [4]f32{ 0.5, -1.0, 0.25, 2.0 };
    const input = [4]f32{ 2.0, 0.5, -2.0, 0.25 };
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), installed_dense_dot4(&weights, &input), 1.0e-6);
}
