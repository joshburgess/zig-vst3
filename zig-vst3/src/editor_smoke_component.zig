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
    const Waveform = plug_core.gui_graph.SnapshotSeries(64);

    meters: MeterBank = MeterBank.init(0.0),
    waveform: Waveform = Waveform.init(),
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
        if (self.waveform.producing()) {
            var points: [64]plug_core.gui_graph.Point = undefined;
            const count = @min(context.frameCount(), points.len);
            if (context.outputChannel(0)) |output| {
                for (points[0..count], 0..) |*point, index| {
                    const source_index = if (count <= 1) 0 else index * (context.frameCount() - 1) / (count - 1);
                    point.* = .{
                        .x = if (count <= 1) 0.0 else -1.0 + 2.0 * @as(f64, @floatFromInt(index)) / @as(f64, @floatFromInt(count - 1)),
                        .y = @floatCast(output[source_index]),
                    };
                }
                _ = self.waveform.publish(points[0..count]);
            }
        }
        self.processed_samples +%= context.frameCount();
    }

    pub fn guiTelemetryLoad(self: *EditorSmokeProcessor, source_id: types.uint32) f64 {
        return self.meters.load(source_id) orelse 0.0;
    }

    pub fn guiTelemetryEditorOpened(self: *EditorSmokeProcessor) void {
        self.meters.editorOpened();
        self.waveform.editorOpened();
    }

    pub fn guiTelemetryEditorClosed(self: *EditorSmokeProcessor) void {
        self.meters.editorClosed();
        self.waveform.editorClosed();
    }

    pub fn guiGraphLoad(self: *EditorSmokeProcessor, source_id: types.uint32, output: []plug_core.gui_graph.Point) usize {
        if (source_id != 0) return 0;
        return self.waveform.read(output) orelse 0;
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

    const points = [_]plug_core.gui_graph.Point{
        .{ .x = -1.0, .y = -0.5 },
        .{ .x = 1.0, .y = 0.5 },
    };
    try std.testing.expect(Effect.processorInstance(component).waveform.publish(&points));
    var loaded: [4]plug_core.gui_graph.Point = undefined;
    try std.testing.expectEqual(@as(usize, 2), source.loadGraph(0, &loaded));
    try std.testing.expectEqual(@as(f64, 0.5), loaded[1].y);
    try std.testing.expectEqual(@as(usize, 0), source.loadGraph(1, &loaded));
}
