const std = @import("std");
const realtime_audit = @import("../realtime_audit.zig");
const audio_layout = @import("audio_layout.zig");

pub const HostChange = enum(u4) {
    component_reload,
    audio_io,
    parameter_values,
    latency,
    parameter_titles,
    midi_cc_assignments,
    note_expression,
    io_titles,
    prefetchable_support,
    routing_info,
    keyswitches,
    parameter_id_mapping,
};

pub const HostRequestSink = struct {
    context: *anyopaque,
    mark_change: *const fn (*anyopaque, HostChange) void,
    set_audio_bus_layout: ?*const fn (
        *anyopaque,
        audio_layout.AudioBusDirection,
        usize,
        audio_layout.AudioBusLayout,
    ) bool = null,
    add_auxiliary_audio_bus: ?*const fn (
        *anyopaque,
        audio_layout.AudioBusDirection,
        audio_layout.DynamicAudioBus,
    ) bool = null,
    remove_auxiliary_audio_bus: ?*const fn (
        *anyopaque,
        audio_layout.AudioBusDirection,
        usize,
    ) bool = null,
    dispatch: *const fn (*anyopaque) bool,

    pub fn markChanged(
        self: *HostRequestSink,
        change: HostChange,
    ) void {
        self.mark_change(self.context, change);
    }

    pub fn markChanges(
        self: *HostRequestSink,
        changes: []const HostChange,
    ) void {
        for (changes) |change| self.markChanged(change);
    }

    pub fn markLatencyChanged(self: *HostRequestSink) void {
        self.markChanged(.latency);
    }

    pub fn markIoChanged(self: *HostRequestSink) void {
        self.markChanged(.audio_io);
    }

    pub fn setAudioBusLayout(
        self: *HostRequestSink,
        direction: audio_layout.AudioBusDirection,
        index: usize,
        layout: audio_layout.AudioBusLayout,
    ) bool {
        const set_layout = self.set_audio_bus_layout orelse return false;
        return set_layout(self.context, direction, index, layout);
    }

    pub fn addAuxiliaryAudioBus(
        self: *HostRequestSink,
        direction: audio_layout.AudioBusDirection,
        bus_value: audio_layout.DynamicAudioBus,
    ) bool {
        const add_bus = self.add_auxiliary_audio_bus orelse return false;
        return add_bus(self.context, direction, bus_value);
    }

    pub fn removeAuxiliaryAudioBus(
        self: *HostRequestSink,
        direction: audio_layout.AudioBusDirection,
        auxiliary_index: usize,
    ) bool {
        const remove_bus =
            self.remove_auxiliary_audio_bus orelse return false;
        return remove_bus(
            self.context,
            direction,
            auxiliary_index,
        );
    }

    pub fn dispatchPending(self: *HostRequestSink) bool {
        if (!realtime_audit.observe(.host_call)) return false;
        return self.dispatch(self.context);
    }
};

test "host request dispatch is rejected in a realtime audit scope" {
    const Probe = struct {
        var marked: ?HostChange = null;
        var dispatch_count: usize = 0;

        fn mark(_: *anyopaque, change: HostChange) void {
            marked = change;
        }

        fn dispatch(_: *anyopaque) bool {
            dispatch_count += 1;
            return true;
        }
    };
    var context: u8 = 0;
    var sink = HostRequestSink{
        .context = &context,
        .mark_change = Probe.mark,
        .dispatch = Probe.dispatch,
    };
    Probe.marked = null;
    Probe.dispatch_count = 0;
    sink.markLatencyChanged();
    try std.testing.expectEqual(HostChange.latency, Probe.marked.?);
    const scope = realtime_audit.Scope.enter();
    try std.testing.expect(!sink.dispatchPending());
    const report = scope.leave();
    try std.testing.expectEqual(
        @as(u32, 1),
        report.count(.host_call),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        Probe.dispatch_count,
    );
    try std.testing.expect(sink.dispatchPending());
    try std.testing.expectEqual(
        @as(usize, 1),
        Probe.dispatch_count,
    );
}

test "host request sink forwards typed changes in order" {
    const Probe = struct {
        var changes: [3]HostChange = undefined;
        var count: usize = 0;

        fn mark(_: *anyopaque, change: HostChange) void {
            changes[count] = change;
            count += 1;
        }

        fn dispatch(_: *anyopaque) bool {
            return true;
        }
    };

    var context: u8 = 0;
    var sink = HostRequestSink{
        .context = &context,
        .mark_change = Probe.mark,
        .dispatch = Probe.dispatch,
    };
    Probe.count = 0;
    sink.markChanges(&.{
        .parameter_values,
        .routing_info,
        .parameter_id_mapping,
    });
    try std.testing.expectEqualSlices(
        HostChange,
        &.{
            .parameter_values,
            .routing_info,
            .parameter_id_mapping,
        },
        Probe.changes[0..Probe.count],
    );
}
