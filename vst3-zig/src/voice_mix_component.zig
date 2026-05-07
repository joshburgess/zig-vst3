const ibstream = @import("pluginterfaces/base/ibstream.zig");
const plug_process = @import("zig-plug-core").process;
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const voice_mix_controller = @import("voice_mix_controller.zig");
const zig_plug_effect = @import("zig_plug_effect.zig");

pub const cid = tuid.inlineUid(0x1B74B03C, 0xFA7B4B7D, 0x8B8429F7, 0xA1A1418F);

const VoiceMixProcessor = struct {
    pub fn process(_: VoiceMixProcessor, comptime Sample: type, context: *plug_process.ProcessContext(Sample)) void {
        const gain: Sample = @floatCast(voice_mix_controller.voiceGain());
        for (0..context.outputs.channels.len) |channel| {
            const input = context.inputs.channel(channel) orelse continue;
            const output = context.outputs.channel(channel) orelse continue;
            for (0..context.frameCount()) |sample| {
                output[sample] = input[sample] * gain;
            }
        }
    }
};

const Effect = zig_plug_effect.SimpleStereoEffect(struct {
    pub const component_name = "VoiceMixComponent";
    pub const controller_cid = voice_mix_controller.cid;
    pub const Processor = VoiceMixProcessor;

    pub fn applyParameterChanges(changes: plug_process.ParameterChanges) void {
        voice_mix_controller.applyParameterChanges(changes);
    }

    pub fn readState(state: ?*ibstream.IBStream) types.tresult {
        return voice_mix_controller.readState(state);
    }

    pub fn writeState(state: ?*ibstream.IBStream) types.tresult {
        return voice_mix_controller.writeState(state);
    }
});

pub const create = Effect.create;

test "voice mix component can be created as IComponent" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");

    var out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    try std.testing.expectEqual(@as(types.int32, 1), component_iface.vtable.getBusCount(component_iface, @intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kInput)));
    try std.testing.expect(component_iface.vtable.release(component_iface) >= 1);
}
