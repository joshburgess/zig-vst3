const editor_smoke_controller = @import("editor_smoke_controller.zig");
const editor_smoke_spec = @import("editor_smoke_spec.zig");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const plug_core = @import("zig-vst3-plugin-core");
const plug_process = plug_core.process;
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const zig_vst3_plugin_effect = @import("zig_vst3_plugin_effect.zig");

pub const cid = tuid.inlineUid(0x96F93E47, 0x21084D80, 0xA6A6B8C4, 0x6F94E68F);

const EditorSmokeProcessor = struct {
    const MeterBank = plug_core.gui_telemetry.MeterBank(f64, 4);

    meters: MeterBank = MeterBank.init(0.0),

    pub fn process(self: *EditorSmokeProcessor, parameters: anytype, comptime Sample: type, context: *plug_process.ProcessContext(Sample)) void {
        const gain: Sample = @floatCast(parameters.getNormalizedById(editor_smoke_controller.gain_param_id));
        const telemetry_active = self.meters.producing();
        var peaks = [_]f64{ 0.0, 0.0 };
        for (0..context.outputChannelCount()) |channel| {
            const input = context.inputChannel(channel) orelse continue;
            const output = context.outputChannel(channel) orelse continue;
            for (0..context.frameCount()) |sample| {
                output[sample] = input[sample] * gain;
                if (telemetry_active and channel < peaks.len) {
                    peaks[channel] = @max(peaks[channel], @abs(@as(f64, @floatCast(output[sample]))));
                }
            }
        }
        if (telemetry_active) {
            _ = self.meters.publish(0, @max(peaks[0], peaks[1]));
            _ = self.meters.publish(1, peaks[0]);
            _ = self.meters.publish(2, peaks[1]);
            _ = self.meters.publish(3, 0.0);
        }
    }

    pub fn guiTelemetryLoad(self: *EditorSmokeProcessor, source_id: types.uint32) f64 {
        return self.meters.load(source_id) orelse 0.0;
    }

    pub fn guiTelemetryEditorOpened(self: *EditorSmokeProcessor) void {
        self.meters.editorOpened();
    }

    pub fn guiTelemetryEditorClosed(self: *EditorSmokeProcessor) void {
        self.meters.editorClosed();
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
