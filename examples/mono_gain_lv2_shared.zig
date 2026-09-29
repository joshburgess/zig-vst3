const core = @import("zig-vst3-plugin-core");

pub const MonoGain = struct {
    pub const name = "zig-vst3 Mono Gain";
    pub const vendor = "zig-vst3";
    pub const audio_input_layout: core.plugin.AudioBusLayout = .mono;
    pub const audio_output_layout: core.plugin.AudioBusLayout = .mono;
    pub const allow_dynamic_process_mode = true;
    pub const lv2_freewheeling = true;
    pub const Params = struct {
        gain: core.parameters.FloatParam = .{
            .id = 0,
            .name = "Gain",
            .min = 0.0,
            .max = 2.0,
            .default = 1.0,
        },
    };

    pub fn processWithParameterView(
        _: *@This(),
        context: *core.process.ProcessContext(f32),
        parameters: core.parameters.ParameterView(Params),
    ) void {
        const input = context.inputChannel(0) orelse return;
        const output = context.outputChannel(0) orelse return;
        const gain: f32 = @floatCast(parameters.load("gain"));
        for (input, output) |sample, *destination|
            destination.* = sample * gain;
    }
};

pub const uri = "https://zig-vst3.dev/plugins/mono-gain";
pub const Adapter = core.lv2.CoreAdapter(
    MonoGain,
    uri,
    4096,
);
