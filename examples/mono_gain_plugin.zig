const plug = @import("zig-vst3-plugin");
const std = @import("std");
const vst3 = @import("zig-vst3");

const core = plug.core;
const base = vst3.pluginterfaces.base;
const vst = vst3.pluginterfaces.vst;
const types = base.types;

const Definition = struct {
    restored_count: usize = 0,
    last_tempo_bpm: ?f64 = null,

    pub const name = "zig-vst3 Mono Gain";
    pub const vendor = "zig-vst3";
    pub const url = "https://github.com/joshburgess/zig-vst3";
    pub const audio_input_layout: core.plugin.AudioBusLayout = .mono;
    pub const audio_output_layout: core.plugin.AudioBusLayout = .mono;
    pub const follow_host_transport = true;
    pub const Params = struct {
        gain: core.parameters.FloatParam = .{
            .id = 0,
            .name = "Gain",
            .min = 0.0,
            .max = 2.0,
            .default = 1.0,
        },
    };

    fn processBlock(
        comptime Sample: type,
        context: *core.process.ProcessContext(Sample),
        parameters: core.parameters.ParameterView(Params),
    ) void {
        const input = context.inputChannel(0) orelse return;
        const output = context.outputChannel(0) orelse return;
        const gain: Sample = @floatCast(parameters.load("gain"));
        for (input, output) |sample, *destination|
            destination.* = sample * gain;
    }

    pub fn processWithParameterView(
        self: *@This(),
        context: *core.process.ProcessContext(f32),
        parameters: core.parameters.ParameterView(Params),
    ) void {
        self.last_tempo_bpm = context.hostTempoBpm();
        processBlock(f32, context, parameters);
    }

    pub fn process64WithParameterView(
        self: *@This(),
        context: *core.process.ProcessContext(f64),
        parameters: core.parameters.ParameterView(Params),
    ) void {
        self.last_tempo_bpm = context.hostTempoBpm();
        processBlock(f64, context, parameters);
    }

    pub fn afterStateRestore(self: *@This()) void {
        self.restored_count += 1;
    }

    pub fn latencySamples(_: *const @This()) u32 {
        return 2;
    }

    pub fn tailSamples(_: *const @This()) u32 {
        return 4;
    }
};

pub const Spec = core.plugin.PluginSpec(Definition);
const mono_parameter_set = Spec.ParameterSet.init(.{});

pub const component_cid = vst3.tuid.inlineUid(0x9DFB88F1, 0x2D1C47EF, 0xA6DF8CE4, 0x6A8B3C11);
pub const mono_controller_cid = vst3.tuid.inlineUid(0xE7B36D20, 0xC4F8405D, 0x9C1A5D92, 0x803FC7A4);

const Effect = plug.Vst3Effect(Definition, struct {
    pub const component_name = "MonoGainComponent";
    pub const controller_cid = mono_controller_cid;
});

const Controller = plug.Vst3Controller(
    Definition,
    "MonoGainController",
);

const Factory = vst3.factory.StaticFactory3(.{
    .vendor = Spec.vendor,
    .url = Spec.url,
    .email = Spec.email,
}, &.{
    .{ .cid = component_cid, .category = Spec.component_category, .name = Spec.component_class_name, .create = Effect.create },
    .{ .cid = mono_controller_cid, .category = Spec.controller_category, .name = Spec.controller_class_name, .create = Controller.create },
});

comptime {
    vst3.entry.exportPlugin(Factory);
}

test "mono gain exposes mono buses and arrangements" {
    var component_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, Effect.create(@ptrCast(&vst.ivstcomponent.icomponent_iid), &component_out));
    const component: *vst.ivstcomponent.IComponent = @ptrCast(@alignCast(component_out.?));
    defer _ = component.vtable.release(component);

    var info: vst.ivstcomponent.BusInfo = .{};
    try std.testing.expectEqual(types.kResultOk, component.vtable.getBusInfo(component, @intFromEnum(vst.ivstcomponent.MediaTypes.kAudio), @intFromEnum(vst.ivstcomponent.BusDirections.kInput), 0, &info));
    try std.testing.expectEqual(@as(types.int32, 1), info.channelCount);

    var processor_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, component.vtable.queryInterface(component, &vst.ivstaudioprocessor.iaudio_processor_iid, &processor_out));
    const processor: *vst.ivstaudioprocessor.IAudioProcessor = @ptrCast(@alignCast(processor_out.?));
    defer _ = processor.vtable.release(processor);

    var inputs = [_]vst.vsttypes.SpeakerArrangement{vst.vstspeaker.SpeakerArr.kMono};
    var outputs = [_]vst.vsttypes.SpeakerArrangement{vst.vstspeaker.SpeakerArr.kMono};
    try std.testing.expectEqual(types.kResultOk, processor.vtable.setBusArrangements(processor, &inputs, 1, &outputs, 1));
    inputs[0] = vst.vstspeaker.SpeakerArr.kStereo;
    try std.testing.expectEqual(types.kResultFalse, processor.vtable.setBusArrangements(processor, &inputs, 1, &outputs, 1));
}

test "mono gain runs the host-neutral runtime through VST3 lifecycle and processing" {
    var component_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        Effect.create(
            @ptrCast(&vst.ivstcomponent.icomponent_iid),
            &component_out,
        ),
    );
    const component: *vst.ivstcomponent.IComponent =
        @ptrCast(@alignCast(component_out.?));
    defer _ = component.vtable.release(component);

    var processor_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component.vtable.queryInterface(
            component,
            &vst.ivstaudioprocessor.iaudio_processor_iid,
            &processor_out,
        ),
    );
    const processor: *vst.ivstaudioprocessor.IAudioProcessor =
        @ptrCast(@alignCast(processor_out.?));
    defer _ = processor.vtable.release(processor);

    try std.testing.expectEqual(
        types.kResultOk,
        processor.vtable.canProcessSampleSize(
            processor,
            @intFromEnum(
                vst.ivstaudioprocessor.SymbolicSampleSizes.kSample32,
            ),
        ),
    );
    try std.testing.expectEqual(
        @as(u32, 2),
        processor.vtable.getLatencySamples(processor),
    );
    try std.testing.expectEqual(
        @as(u32, 4),
        processor.vtable.getTailSamples(processor),
    );
    try std.testing.expectEqual(
        types.kResultOk,
        processor.vtable.canProcessSampleSize(
            processor,
            @intFromEnum(
                vst.ivstaudioprocessor.SymbolicSampleSizes.kSample64,
            ),
        ),
    );

    var setup = vst.ivstaudioprocessor.ProcessSetup{
        .processMode = @intFromEnum(
            vst.ivstaudioprocessor.ProcessModes.kRealtime,
        ),
        .symbolicSampleSize = @intFromEnum(
            vst.ivstaudioprocessor.SymbolicSampleSizes.kSample32,
        ),
        .sampleRate = 48_000.0,
        .maxSamplesPerBlock = 3,
    };
    try std.testing.expectEqual(
        types.kResultOk,
        processor.vtable.setupProcessing(processor, &setup),
    );
    try std.testing.expectEqual(
        types.kResultOk,
        component.vtable.setActive(component, 1),
    );
    defer _ = component.vtable.setActive(component, 0);

    const Changes = vst3.vst_parameter_changes.ParameterChanges(1, 1);
    var changes = Changes{};
    const gain_queue = changes.addQueue(0).?;
    try std.testing.expectEqual(
        types.kResultOk,
        gain_queue.appendPoint(0, 0.25),
    );

    var input_samples = [_]f32{ 1.0, -0.5, 0.25 };
    var output_samples = [_]f32{ 0.0, 0.0, 0.0 };
    var input_channel_ptrs = [_][*]f32{&input_samples};
    var output_channel_ptrs = [_][*]f32{&output_samples};
    var inputs = [_]vst.ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 1,
        .channelBuffers = .{
            .channelBuffers32 = input_channel_ptrs[0..].ptr,
        },
    }};
    var outputs = [_]vst.ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 1,
        .channelBuffers = .{
            .channelBuffers32 = output_channel_ptrs[0..].ptr,
        },
    }};
    var process_context =
        vst.ivstprocesscontext.ProcessContext{
            .state = vst.ivstprocesscontext.StatesAndFlags.kPlaying |
                vst.ivstprocesscontext.StatesAndFlags.kTempoValid,
            .sampleRate = 48_000.0,
            .tempo = 137.0,
        };
    var data = vst.ivstaudioprocessor.ProcessData{
        .numInputs = 1,
        .numOutputs = 1,
        .inputs = &inputs,
        .outputs = &outputs,
        .numSamples = input_samples.len,
        .symbolicSampleSize = @intFromEnum(
            vst.ivstaudioprocessor.SymbolicSampleSizes.kSample32,
        ),
        .inputParameterChanges = changes.asInterface(),
        .processContext = &process_context,
    };

    try std.testing.expectEqual(
        types.kResultOk,
        processor.vtable.process(processor, &data),
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0.5, -0.25, 0.125 },
        &output_samples,
    );
    try std.testing.expectEqual(
        @as(f64, 0.25),
        Effect.getParameterNormalized(component, 0),
    );
    try std.testing.expectEqual(
        @as(?f64, 137.0),
        Effect.processorInstance(component)
            .runtime.instance.plugin.last_tempo_bpm,
    );

    var state_stream = vst3.vst_stream.FixedBufferStream(256){};
    try std.testing.expectEqual(
        types.kResultOk,
        component.vtable.getState(
            component,
            state_stream.asStream(),
        ),
    );
    try std.testing.expectEqual(
        types.kResultOk,
        Effect.setParameterNormalized(component, 0, 0.9),
    );
    var restored_position: types.int64 = -1;
    try std.testing.expectEqual(
        types.kResultOk,
        state_stream.asStream().vtable.seek(
            state_stream.asStream(),
            0,
            @intFromEnum(
                base.ibstream.IStreamSeekMode.kIBSeekSet,
            ),
            &restored_position,
        ),
    );
    try std.testing.expectEqual(
        types.kResultOk,
        component.vtable.setState(
            component,
            state_stream.asStream(),
        ),
    );
    const adapter = Effect.processorInstance(component);
    try std.testing.expectEqual(
        @as(?f64, 0.25),
        adapter.runtime.instance.parameterValuesConst().load(0),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        adapter.runtime.instance.plugin.restored_count,
    );
}
