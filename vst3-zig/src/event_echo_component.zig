const event_echo_controller = @import("event_echo_controller.zig");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const plug_process = @import("zig-plug-core").process;
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const zig_plug_effect = @import("zig_plug_effect.zig");

pub const cid = tuid.inlineUid(0xD9C97C5A, 0x062A4B52, 0x9C3DF51C, 0xFFAC4B41);

const EventEchoProcessor = struct {
    pub fn process(_: EventEchoProcessor, comptime Sample: type, context: *plug_process.ProcessContext(Sample)) void {
        for (0..context.outputs.channels.len) |channel| {
            const input = context.inputs.channel(channel) orelse continue;
            const output = context.outputs.channel(channel) orelse continue;
            for (0..context.frameCount()) |sample| {
                output[sample] = input[sample];
            }
        }

        const writer = context.output_events orelse return;
        for (context.events.items) |event| {
            writer.append(event) catch {};
        }
    }
};

const Effect = zig_plug_effect.SimpleStereoEffect(struct {
    pub const component_name = "EventEchoComponent";
    pub const controller_cid = event_echo_controller.cid;
    pub const event_output = true;
    pub const Processor = EventEchoProcessor;

    pub fn applyParameterChanges(changes: plug_process.ParameterChanges) void {
        event_echo_controller.applyParameterChanges(changes);
    }

    pub fn readState(state: ?*ibstream.IBStream) types.tresult {
        return event_echo_controller.readState(state);
    }

    pub fn writeState(state: ?*ibstream.IBStream) types.tresult {
        return event_echo_controller.writeState(state);
    }
});

pub const create = Effect.create;

test "event echo component can be created with input and output event buses" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");

    var out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    try std.testing.expectEqual(@as(types.int32, 1), component_iface.vtable.getBusCount(component_iface, @intFromEnum(ivstcomponent.MediaTypes.kEvent), @intFromEnum(ivstcomponent.BusDirections.kInput)));
    try std.testing.expectEqual(@as(types.int32, 1), component_iface.vtable.getBusCount(component_iface, @intFromEnum(ivstcomponent.MediaTypes.kEvent), @intFromEnum(ivstcomponent.BusDirections.kOutput)));
    try std.testing.expect(component_iface.vtable.release(component_iface) >= 1);
}
