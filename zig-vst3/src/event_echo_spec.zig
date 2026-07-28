const plug = @import("zig-vst3-plugin-core");

pub const EventEchoPlugin = struct {
    pub const name = "zig-vst3 Event Echo";
    pub const vendor = "zig-vst3";
    pub const url = "https://github.com/joshburgess/zig-vst3";
    pub const event_output = true;
    pub const Params = struct {};

    fn processBlock(
        comptime Sample: type,
        context: *plug.process.ProcessContext(Sample),
    ) void {
        for (0..context.outputChannelCount()) |channel| {
            const input = context.inputChannel(channel) orelse continue;
            const output = context.outputChannel(channel) orelse continue;
            @memcpy(output, input);
        }
        _ = context.appendOutputEventsIfPossible(
            context.inputEvents(),
        );
    }

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
};

pub const Spec = plug.plugin.PluginSpec(EventEchoPlugin);
pub const parameter_set = Spec.ParameterSet.init(.{});
pub const component_class_name = Spec.component_class_name;
pub const controller_class_name = Spec.controller_class_name;
