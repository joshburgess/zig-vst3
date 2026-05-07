const ibstream = @import("pluginterfaces/base/ibstream.zig");
const note_gate_controller = @import("note_gate_controller.zig");
const plug_process = @import("zig-plug-core").process;
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const zig_plug_effect = @import("zig_plug_effect.zig");

pub const cid = tuid.inlineUid(0x70E3A630, 0x5EE54F09, 0x94C968A8, 0x22947A9F);

const NoteGateProcessor = struct {
    pub fn process(_: NoteGateProcessor, comptime Sample: type, context: *plug_process.ProcessContext(Sample)) void {
        const gate_open = context.events.countKind(.note_on) > 0;
        for (0..context.outputs.channels.len) |channel| {
            const input = context.inputs.channel(channel) orelse continue;
            const output = context.outputs.channel(channel) orelse continue;
            for (0..context.frameCount()) |sample| {
                output[sample] = if (gate_open) input[sample] else 0;
            }
        }
    }
};

const Effect = zig_plug_effect.SimpleStereoEffect(struct {
    pub const component_name = "NoteGateComponent";
    pub const controller_cid = note_gate_controller.cid;
    pub const Processor = NoteGateProcessor;

    pub fn applyParameterChanges(changes: plug_process.ParameterChanges) void {
        note_gate_controller.applyParameterChanges(changes);
    }

    pub fn readState(state: ?*ibstream.IBStream) types.tresult {
        return note_gate_controller.readState(state);
    }

    pub fn writeState(state: ?*ibstream.IBStream) types.tresult {
        return note_gate_controller.writeState(state);
    }
});

pub const create = Effect.create;

test "note gate component can be created as IComponent" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");

    var out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    try std.testing.expectEqual(@as(types.int32, 1), component_iface.vtable.getBusCount(component_iface, @intFromEnum(ivstcomponent.MediaTypes.kEvent), @intFromEnum(ivstcomponent.BusDirections.kInput)));
    try std.testing.expect(component_iface.vtable.release(component_iface) >= 1);
}
