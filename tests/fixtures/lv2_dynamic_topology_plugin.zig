const core = @import("zig-vst3-plugin-core");

const DynamicTopologyProbe = struct {
    const Topology =
        core.plugin.BoundedDynamicAudioBusTopology(1);

    pub const name = "LV2 Dynamic Topology Probe";
    pub const vendor = "zig-vst3";
    pub const Params = struct {};
    pub const event_input = false;
    pub const maximum_auxiliary_audio_buses = 1;
    pub const audio_bus_topology = makeTopology();

    fn makeTopology() Topology {
        const stereo = core.plugin.DynamicAudioBus.fixed(
            .stereo,
            true,
        ) catch unreachable;
        const inactive_stereo = core.plugin.DynamicAudioBus.fixed(
            .stereo,
            false,
        ) catch unreachable;
        var topology = Topology.init(
            stereo,
            stereo,
        ) catch unreachable;
        _ = topology.addAuxiliary(
            .input,
            inactive_stereo,
        ) catch unreachable;
        _ = topology.addAuxiliary(
            .output,
            inactive_stereo,
        ) catch unreachable;
        return topology;
    }

    pub fn process(
        _: *@This(),
        context: *core.process.BoundedProcessContext(
            f32,
            maximum_auxiliary_audio_buses,
        ),
    ) void {
        for (0..2) |channel_index| {
            const input = context.inputChannel(channel_index) orelse
                return;
            const output = context.outputChannel(channel_index) orelse
                return;
            const auxiliary_input = context.sidechainInputChannel(
                channel_index,
            );
            for (input, output, 0..) |sample, *destination, frame_index| {
                destination.* = sample + if (auxiliary_input) |channel|
                    channel[frame_index]
                else
                    0.0;
            }
            if (context.auxiliaryOutputChannel(channel_index)) |auxiliary| {
                for (input, auxiliary) |sample, *destination|
                    destination.* = sample * 2.0;
            }
        }
    }
};

const Adapter = core.lv2.CoreAdapter(
    DynamicTopologyProbe,
    "https://zig-vst3.dev/tests/lv2-dynamic-topology",
    64,
);

pub export fn lv2_descriptor(
    index: u32,
) callconv(.c) ?*const core.lv2.Descriptor {
    return Adapter.descriptorAt(index);
}
