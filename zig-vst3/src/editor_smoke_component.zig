const editor_smoke_controller = @import("editor_smoke_controller.zig");
const editor_smoke_spec = @import("editor_smoke_spec.zig");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
const gui_telemetry_source = @import("gui_telemetry_source.zig");
const plug_core = @import("zig-vst3-plugin-core");
const plug_process = plug_core.process;
const std = @import("std");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const zig_vst3_plugin_effect = @import("zig_vst3_plugin_effect.zig");

pub const cid = tuid.inlineUid(0x96F93E47, 0x21084D80, 0xA6A6B8C4, 0x6F94E68F);

const EditorSmokeProcessor = struct {
    const MeterBank = plug_core.gui_telemetry.MeterBank(f64, 5);
    const Waveform = plug_core.gui_graph.WaveformCapture(64);
    const Spectrum = plug_core.gui_graph.SpectrumAnalyzer(128);

    meters: MeterBank = MeterBank.init(0.0),
    waveform: Waveform = Waveform.init(),
    spectrum: Spectrum = Spectrum.init(),
    processed_samples: u64 = 0,

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
            _ = self.meters.publish(4, @floatFromInt((self.processed_samples / 6_000) % 8));
        }
        if (context.outputChannel(0)) |output| {
            _ = self.waveform.capture(output);
            _ = self.spectrum.push(output, context.sampleRate());
        }
        self.processed_samples +%= context.frameCount();
    }

    pub fn guiTelemetryLoad(self: *EditorSmokeProcessor, source_id: types.uint32) f64 {
        return self.meters.load(source_id) orelse 0.0;
    }

    pub fn guiTelemetryEditorOpened(self: *EditorSmokeProcessor) void {
        self.meters.editorOpened();
        self.waveform.editorOpened();
        self.spectrum.editorOpened();
    }

    pub fn guiTelemetryEditorClosed(self: *EditorSmokeProcessor) void {
        self.meters.editorClosed();
        self.waveform.editorClosed();
        self.spectrum.editorClosed();
    }

    pub fn guiGraphLoad(self: *EditorSmokeProcessor, source_id: types.uint32, output: []plug_core.gui_graph.Point) usize {
        return switch (source_id) {
            0 => self.waveform.read(output) orelse 0,
            1 => self.spectrum.read(output) orelse 0,
            else => 0,
        };
    }
};

const Effect = zig_vst3_plugin_effect.SimpleStereoEffect(struct {
    pub const component_name = "EditorSmokeComponent";
    pub const controller_cid = editor_smoke_controller.cid;
    pub const gui_note_input = true;
    pub const Params = editor_smoke_spec.Spec.Params;
    pub const parameter_set = &editor_smoke_spec.parameter_set;
    pub const Processor = EditorSmokeProcessor;
});

pub const create = Effect.create;

test "editor smoke graph source publishes bounded waveform snapshots" {
    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Effect.create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    const component: *ivstcomponent.IComponent = @ptrCast(@alignCast(out orelse return error.MissingComponent));
    defer _ = component.vtable.release(component);

    const source = gui_telemetry_source.query(component) orelse return error.MissingTelemetry;
    defer source.release();
    source.editorOpened();
    defer source.editorClosed();

    const samples = [_]f64{ -0.5, 0.5 };
    try std.testing.expect(Effect.processorInstance(component).waveform.capture(&samples));
    var loaded: [4]plug_core.gui_graph.Point = undefined;
    try std.testing.expectEqual(@as(usize, 2), source.loadGraph(0, &loaded));
    try std.testing.expectEqual(@as(f64, 0.5), loaded[1].y);
    var tone: [128]f64 = undefined;
    for (&tone, 0..) |*sample, index| {
        sample.* = std.math.sin(std.math.tau * 8.0 * @as(f64, @floatFromInt(index)) / 128.0);
    }
    try std.testing.expect(Effect.processorInstance(component).spectrum.push(&tone, 48_000.0));
    var spectrum: [64]plug_core.gui_graph.Point = undefined;
    try std.testing.expectEqual(@as(usize, 64), source.loadGraph(1, &spectrum));
    try std.testing.expect(spectrum[7].y > -1.0);
    try std.testing.expectEqual(@as(usize, 0), source.loadGraph(2, &loaded));
}
