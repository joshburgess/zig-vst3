const editor_smoke_controller = @import("editor_smoke_controller.zig");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const plug_process = @import("zig-vst3-plugin-core").process;
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const zig_vst3_plugin_effect = @import("zig_vst3_plugin_effect.zig");

pub const cid = tuid.inlineUid(0x96F93E47, 0x21084D80, 0xA6A6B8C4, 0x6F94E68F);

const EditorSmokeProcessor = struct {
    pub fn process(_: EditorSmokeProcessor, comptime Sample: type, context: *plug_process.ProcessContext(Sample)) void {
        const gain: Sample = @floatCast(editor_smoke_controller.gain());
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
    pub const Processor = EditorSmokeProcessor;

    pub fn applyParameterChanges(changes: plug_process.ParameterChanges) void {
        editor_smoke_controller.applyParameterChanges(changes);
    }

    pub fn readState(state: ?*ibstream.IBStream) types.tresult {
        return editor_smoke_controller.readState(state);
    }

    pub fn writeState(state: ?*ibstream.IBStream) types.tresult {
        return editor_smoke_controller.writeState(state);
    }
});

pub const create = Effect.create;
