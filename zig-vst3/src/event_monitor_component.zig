const event_monitor_controller = @import("event_monitor_controller.zig");
const event_monitor_spec = @import("event_monitor_spec.zig");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const plug_process = @import("zig-vst3-plugin-core").process;
const std = @import("std");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const zig_vst3_plugin_effect = @import("zig_vst3_plugin_effect.zig");

pub const cid = tuid.inlineUid(0x4E0A7C91, 0x2B8D4AAE, 0xA82F3C19, 0x6D57E204);

const EventMonitorState = struct {
    note_on_count: usize = 0,
    note_off_count: usize = 0,
    midi_cc_count: usize = 0,
    pitch_bend_count: usize = 0,
    aftertouch_count: usize = 0,
    latest_event_offset: ?usize = null,
    latest_midi_cc_value: f64 = 0.0,

    fn reset(self: *EventMonitorState) void {
        self.* = .{};
    }

    fn process(self: *EventMonitorState, comptime Sample: type, context: *plug_process.ProcessContext(Sample)) void {
        self.note_on_count = context.countEvents(.note_on);
        self.note_off_count = context.countEvents(.note_off);
        self.pitch_bend_count = context.countEvents(.pitch_bend);
        self.aftertouch_count = context.countEvents(.aftertouch);
        self.latest_event_offset = context.latestEventOffset();
        self.latest_midi_cc_value = 0.0;
        self.midi_cc_count = 0;

        var cc_events = context.inputEventsOfKind(.midi_cc);
        while (cc_events.next()) |event| {
            const cc = event.asMidiCC().?;
            self.midi_cc_count += 1;
            self.latest_midi_cc_value = cc.value;
        }
    }
};

var monitor = EventMonitorState{};

fn resetEventMonitorState() void {
    monitor.reset();
}

const EventMonitorProcessor = struct {
    pub fn process(_: EventMonitorProcessor, comptime Sample: type, context: *plug_process.ProcessContext(Sample)) void {
        monitor.process(Sample, context);
    }
};

const Effect = zig_vst3_plugin_effect.SimpleStereoEffect(struct {
    pub const component_name = "EventMonitorComponent";
    pub const controller_cid = event_monitor_controller.cid;
    pub const event_input = event_monitor_spec.Spec.event_input;
    pub const audio_output = event_monitor_spec.Spec.audio_output;
    pub const Processor = EventMonitorProcessor;

    pub fn resetProcessState() void {
        resetEventMonitorState();
    }

    pub fn applyParameterChanges(changes: plug_process.ParameterChanges) void {
        event_monitor_controller.applyParameterChanges(changes);
    }

    pub fn readState(state: ?*ibstream.IBStream) types.tresult {
        return event_monitor_controller.readState(state);
    }

    pub fn writeState(state: ?*ibstream.IBStream) types.tresult {
        return event_monitor_controller.writeState(state);
    }
});

pub const create = Effect.create;

test "event monitor component can be created as an input-only analyzer" {
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");

    var out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    try std.testing.expectEqual(@as(types.int32, 1), component_iface.vtable.getBusCount(component_iface, @intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kInput)));
    try std.testing.expectEqual(@as(types.int32, 0), component_iface.vtable.getBusCount(component_iface, @intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kOutput)));
    try std.testing.expectEqual(@as(types.int32, 1), component_iface.vtable.getBusCount(component_iface, @intFromEnum(ivstcomponent.MediaTypes.kEvent), @intFromEnum(ivstcomponent.BusDirections.kInput)));
    try std.testing.expect(component_iface.vtable.release(component_iface) >= 1);
}

test "event monitor processor summarizes input events without audio output" {
    var local_monitor = EventMonitorState{};
    const input = [_]f32{ 0.0, 0.0, 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{};
    const events = [_]plug_process.Event{
        plug_process.Event.noteOn(1, 0, 60, 0.75),
        plug_process.Event.midiCc(2, 0, 74, 0.5),
        plug_process.Event.pitchBend(3, 0, 0.25),
        plug_process.Event.aftertouch(3, 0, 64, 0.5),
        plug_process.Event.noteOff(3, 0, 60, 0.0),
    };
    var context = try plug_process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
    });

    local_monitor.process(f32, &context);

    try std.testing.expectEqual(@as(usize, 1), local_monitor.note_on_count);
    try std.testing.expectEqual(@as(usize, 1), local_monitor.note_off_count);
    try std.testing.expectEqual(@as(usize, 1), local_monitor.midi_cc_count);
    try std.testing.expectEqual(@as(usize, 1), local_monitor.pitch_bend_count);
    try std.testing.expectEqual(@as(usize, 1), local_monitor.aftertouch_count);
    try std.testing.expectEqual(@as(?usize, 3), local_monitor.latest_event_offset);
    try std.testing.expectEqual(@as(f64, 0.5), local_monitor.latest_midi_cc_value);
}
