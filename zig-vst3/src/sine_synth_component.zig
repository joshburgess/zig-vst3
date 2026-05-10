const ibstream = @import("pluginterfaces/base/ibstream.zig");
const plug_process = @import("zig-vst3-plugin-core").process;
const sine_synth_controller = @import("sine_synth_controller.zig");
const sine_synth_spec = @import("sine_synth_spec.zig");
const std = @import("std");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const zig_vst3_plugin_effect = @import("zig_vst3_plugin_effect.zig");

pub const cid = tuid.inlineUid(0x8C7F6A10, 0x4D2B4A9F, 0xA515C8A1, 0xBC1E3D72);

const SineSynthState = struct {
    active: bool = false,
    note: i16 = 69,
    phase: f64 = 0.0,

    fn process(self: *SineSynthState, comptime Sample: type, context: *plug_process.ProcessContext(Sample)) void {
        context.clearOutputs();

        var segments = context.processBlockSegments();
        while (segments.next()) |segment| {
            self.applyEventsAt(Sample, context, segment.start_offset);
            if (!self.active) continue;

            const level: Sample = @floatCast(context.parameterNormalizedAtOrBeforeOr(
                sine_synth_controller.level_param_id,
                segment.start_offset,
                sine_synth_controller.level(),
            ));
            const step = midiFrequency(self.note) / context.sample_rate;
            for (segment.start_offset..segment.end_offset) |sample| {
                const value: Sample = @floatCast(std.math.sin(self.phase * std.math.tau) * @as(f64, @floatCast(level)));
                for (0..context.outputChannelCount()) |channel| {
                    const output = context.outputChannel(channel) orelse continue;
                    output[sample] = value;
                }
                self.phase += step;
                if (self.phase >= 1.0) self.phase -= @floor(self.phase);
            }
        }
    }

    fn applyEventsAt(self: *SineSynthState, comptime Sample: type, context: *plug_process.ProcessContext(Sample), sample_offset: usize) void {
        var events = context.inputEventsAtOffset(sample_offset);
        while (events.next()) |event| {
            if (event.asNoteAttack()) |note| {
                self.active = true;
                self.note = note.pitch;
                self.phase = 0.0;
            } else if (event.asNoteRelease()) |note| {
                if (note.pitch == self.note) self.active = false;
            }
        }
    }

    fn midiFrequency(note: i16) f64 {
        return 440.0 * std.math.pow(f64, 2.0, (@as(f64, @floatFromInt(note)) - 69.0) / 12.0);
    }
};

var synth = SineSynthState{};

fn resetSineSynthState() void {
    synth = .{};
}

const SineSynthProcessor = struct {
    pub fn process(_: SineSynthProcessor, comptime Sample: type, context: *plug_process.ProcessContext(Sample)) void {
        synth.process(Sample, context);
    }
};

const Effect = zig_vst3_plugin_effect.SimpleStereoEffect(struct {
    pub const component_name = "SineSynthComponent";
    pub const controller_cid = sine_synth_controller.cid;
    pub const event_input = sine_synth_spec.Spec.event_input;
    pub const audio_input = sine_synth_spec.Spec.audio_input;
    pub const Processor = SineSynthProcessor;

    pub fn resetProcessState() void {
        resetSineSynthState();
    }

    pub fn applyParameterChanges(changes: plug_process.ParameterChanges) void {
        sine_synth_controller.applyParameterChanges(changes);
    }

    pub fn readState(state: ?*ibstream.IBStream) types.tresult {
        return sine_synth_controller.readState(state);
    }

    pub fn writeState(state: ?*ibstream.IBStream) types.tresult {
        return sine_synth_controller.writeState(state);
    }
});

pub const create = Effect.create;

test "sine synth component can be created as IComponent" {
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");

    var out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    try std.testing.expectEqual(@as(types.int32, 0), component_iface.vtable.getBusCount(component_iface, @intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kInput)));
    try std.testing.expectEqual(@as(types.int32, 1), component_iface.vtable.getBusCount(component_iface, @intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kOutput)));
    try std.testing.expectEqual(@as(types.int32, 1), component_iface.vtable.getBusCount(component_iface, @intFromEnum(ivstcomponent.MediaTypes.kEvent), @intFromEnum(ivstcomponent.BusDirections.kInput)));
    try std.testing.expect(component_iface.vtable.release(component_iface) >= 1);
}

test "sine synth processor responds to note events and level automation" {
    var local_synth = SineSynthState{};
    var output = [_]f32{ 0.0, 0.0, 0.0, 0.0 };
    const input_channels = [_][]const f32{};
    const output_channels = [_][]f32{&output};
    const events = [_]plug_process.Event{
        plug_process.Event.noteOn(0, 0, 69, 1.0),
    };
    const changes = [_]plug_process.ParameterChange{
        .{ .id = sine_synth_controller.level_param_id, .sample_offset = 2, .normalized = 0.0 },
    };
    var context = try plug_process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
        .parameter_changes = &changes,
    });

    local_synth.process(f32, &context);

    try std.testing.expectEqual(@as(f32, 0.0), output[0]);
    try std.testing.expect(output[1] > 0.0);
    try std.testing.expectEqual(@as(f32, 0.0), output[2]);
    try std.testing.expectEqual(@as(f32, 0.0), output[3]);
    try std.testing.expect(local_synth.active);
}

test "sine synth processor treats zero-velocity note-on as note-off" {
    var local_synth = SineSynthState{};
    var output = [_]f32{ 0.0, 0.0, 0.0, 0.0 };
    const input_channels = [_][]const f32{};
    const output_channels = [_][]f32{&output};
    const events = [_]plug_process.Event{
        plug_process.Event.noteOn(0, 0, 69, 1.0),
        plug_process.Event.noteOn(2, 0, 69, 0.0),
    };
    var context = try plug_process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
    });

    local_synth.process(f32, &context);

    try std.testing.expectEqual(@as(f32, 0.0), output[0]);
    try std.testing.expect(output[1] > 0.0);
    try std.testing.expectEqual(@as(f32, 0.0), output[2]);
    try std.testing.expectEqual(@as(f32, 0.0), output[3]);
    try std.testing.expect(!local_synth.active);
}

test "sine synth component uses spec default level" {
    try std.testing.expectEqual(@as(f64, 0.1), sine_synth_spec.default_level);
}

test "sine synth component resets process state when deactivated" {
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");

    resetSineSynthState();
    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    var output = [_]f32{ 0.0, 0.0 };
    const input_channels = [_][]const f32{};
    const output_channels = [_][]f32{&output};
    const events = [_]plug_process.Event{
        plug_process.Event.noteOn(0, 0, 69, 1.0),
    };
    var context = try plug_process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
    });
    (SineSynthProcessor{}).process(f32, &context);
    try std.testing.expect(synth.active);

    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.setActive(component_iface, 0));
    try std.testing.expect(!synth.active);
    try std.testing.expectEqual(@as(i16, 69), synth.note);
    try std.testing.expectEqual(@as(f64, 0.0), synth.phase);
}
