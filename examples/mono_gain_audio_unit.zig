const plug = @import("zig-vst3-plugin-core");
const std = @import("std");

const MonoGain = struct {
    pub const name = "zig-vst3 Mono Gain";
    pub const vendor = "zig-vst3";
    pub const audio_input_layout: plug.plugin.AudioBusLayout = .mono;
    pub const audio_output_layout: plug.plugin.AudioBusLayout = .mono;
    pub const Params = struct {
        gain: plug.parameters.FloatParam = .{
            .id = 0,
            .name = "Gain",
            .min = 0.0,
            .max = 2.0,
            .default = 1.0,
        },
    };

    pub fn process(
        _: *@This(),
        context: *plug.process.ProcessContext(f32),
    ) void {
        processBlock(f32, context);
    }

    pub fn process64(
        _: *@This(),
        context: *plug.process.ProcessContext(f64),
    ) void {
        processBlock(f64, context);
    }

    fn processBlock(
        comptime Sample: type,
        context: *plug.process.ProcessContext(Sample),
    ) void {
        const input = context.inputChannel(0) orelse return;
        const output = context.outputChannel(0) orelse return;
        for (input, output, 0..) |sample, *destination, offset| {
            const gain: Sample = @floatCast(
                context.parameterNormalizedAtOrBeforeOr(
                    0,
                    offset,
                    0.5,
                ) * 2.0,
            );
            destination.* = sample * gain;
        }
    }
};

pub const component_description =
    plug.audio_unit_v2.AudioComponentDescription{
        .component_type = 0x61756678,
        .component_subtype = 0x5a4d476e,
        .component_manufacturer = 0x5a696733,
        .component_flags = 0,
        .component_flags_mask = 0,
    };

const Factory = plug.audio_unit_v2.NativeComponentFactory(
    MonoGain,
    4096,
    component_description,
    44_100.0,
    512,
);

export fn ZigVst3MonoGainFactory(
    description: ?*const plug.audio_unit_v2.AudioComponentDescription,
) callconv(.c) ?*plug.audio_unit_v2.AudioComponentPlugInInterface {
    return Factory.create(description);
}

test "Mono Gain Audio Unit factory exports the expected component" {
    const interface = ZigVst3MonoGainFactory(
        &component_description,
    ) orelse return error.FactoryCreationFailed;
    const opaque_interface: *anyopaque = @ptrCast(interface);
    const instance: plug.audio_unit_v2.AudioComponentInstance =
        @ptrFromInt(1);
    try std.testing.expectEqual(
        plug.audio_unit_v2.status.success,
        interface.open(opaque_interface, instance),
    );
    try std.testing.expectEqual(
        plug.audio_unit_v2.status.success,
        interface.close(opaque_interface),
    );
}
