const editor_smoke_controller = @import("editor_smoke_controller.zig");
const editor_smoke_spec = @import("editor_smoke_spec.zig");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const plug_process = @import("zig-vst3-plugin-core").process;
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const zig_vst3_plugin_effect = @import("zig_vst3_plugin_effect.zig");

pub const cid = tuid.inlineUid(0x96F93E47, 0x21084D80, 0xA6A6B8C4, 0x6F94E68F);

const EditorSmokeProcessor = struct {
    pub fn process(_: *EditorSmokeProcessor, parameters: anytype, comptime Sample: type, context: *plug_process.ProcessContext(Sample)) void {
        const gain: Sample = @floatCast(parameters.getNormalizedById(editor_smoke_controller.gain_param_id));
        for (0..context.outputChannelCount()) |channel| {
            const input = context.inputChannel(channel) orelse continue;
            const output = context.outputChannel(channel) orelse continue;
            for (0..context.frameCount()) |sample| {
                output[sample] = input[sample] * gain;
            }
        }
    }
};

const Effect = zig_vst3_plugin_effect.SimpleStereoEffect(struct {
    pub const component_name = "EditorSmokeComponent";
    pub const controller_cid = editor_smoke_controller.cid;
    pub const Params = editor_smoke_spec.Spec.Params;
    pub const parameter_set = &editor_smoke_spec.parameter_set;
    pub const Processor = EditorSmokeProcessor;
});

pub const create = Effect.create;
