const plug = @import("zig-vst3-plugin-core");
const std = @import("std");

const AuxiliaryOutputSplitter = struct {
    pub const name = "zig-vst3 Auxiliary Output Splitter";
    pub const vendor = "zig-vst3";
    pub const audio_input_layout: plug.plugin.AudioBusLayout = .stereo;
    pub const audio_output_layout: plug.plugin.AudioBusLayout = .stereo;
    pub const audio_auxiliary_output_layouts: []const plug.plugin.AudioBusLayout = &.{ .mono, .stereo };
    pub const Params = struct {};

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
        for (0..context.outputChannelCount()) |channel_index| {
            const input = context.inputChannel(channel_index) orelse
                continue;
            const output = context.outputChannel(channel_index) orelse
                continue;
            for (input, output) |sample, *destination| {
                destination.* = sample;
            }
        }

        const left = context.inputChannel(0) orelse return;
        const right = context.inputChannel(1) orelse return;
        if (context.auxiliaryOutputBus(0)) |mono_bus| {
            if (mono_bus.channel(0)) |mono| {
                for (mono, left, right) |*destination, lhs, rhs|
                    destination.* = (lhs + rhs) * 0.5;
            }
        }
        if (context.auxiliaryOutputBus(1)) |stereo_bus| {
            if (stereo_bus.channel(0)) |output| {
                for (left, output) |sample, *destination| {
                    destination.* = sample;
                }
            }
            if (stereo_bus.channel(1)) |output| {
                for (right, output) |sample, *destination| {
                    destination.* = sample;
                }
            }
        }
    }
};

pub const component_description =
    plug.audio_unit_v2.AudioComponentDescription{
        .component_type = 0x61756678,
        .component_subtype = 0x5a417578,
        .component_manufacturer = 0x5a696733,
        .component_flags = 0,
        .component_flags_mask = 0,
    };

const Factory = plug.audio_unit_v2.NativeComponentFactory(
    AuxiliaryOutputSplitter,
    4096,
    component_description,
    44_100.0,
    512,
);

export fn ZigVst3AuxOutputSplitterFactory(
    description: ?*const plug.audio_unit_v2.AudioComponentDescription,
) callconv(.c) ?*plug.audio_unit_v2.AudioComponentPlugInInterface {
    return Factory.create(description);
}

test "Auxiliary Output Splitter Audio Unit exports three output buses" {
    const audio_unit = @import("zig-vst3-plugin-core").audio_unit_v2;
    const interface = ZigVst3AuxOutputSplitterFactory(
        &component_description,
    ) orelse return error.FactoryCreationFailed;
    const opaque_interface: *anyopaque = @ptrCast(interface);
    try std.testing.expectEqual(
        audio_unit.status.success,
        interface.open(opaque_interface, @ptrFromInt(1)),
    );
    const GetPropertyProc = *const fn (
        *anyopaque,
        audio_unit.AudioUnitPropertyID,
        audio_unit.AudioUnitScope,
        audio_unit.AudioUnitElement,
        ?*anyopaque,
        ?*u32,
    ) callconv(.c) audio_unit.OSStatus;
    const get_property: GetPropertyProc = @ptrCast(@alignCast(
        interface.lookup(audio_unit.selector.get_property) orelse
            return error.MissingGetProperty,
    ));
    var output_bus_count: u32 = 0;
    var size: u32 = @sizeOf(u32);
    try std.testing.expectEqual(
        audio_unit.status.success,
        get_property(
            opaque_interface,
            audio_unit.property.element_count,
            audio_unit.scope.output,
            0,
            &output_bus_count,
            &size,
        ),
    );
    try std.testing.expectEqual(@as(u32, 3), output_bus_count);
    try std.testing.expectEqual(
        audio_unit.status.success,
        interface.close(opaque_interface),
    );
}
