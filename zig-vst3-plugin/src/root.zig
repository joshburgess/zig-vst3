const std = @import("std");
const vst3 = @import("zig-vst3");
const vst3_adapter_mod =
    vst3.zig_vst3_plugin_runtime_adapter;

pub const core = @import("zig-vst3-plugin-core");
pub const gui = core.gui;
pub const editor_state = core.editor_state;
pub const gui_preset_browser = core.gui_preset_browser;
pub const gui_telemetry = core.gui_telemetry;
pub const gui_graph = core.gui_graph;
pub const gui_piano = core.gui_piano;
pub const gui_step_sequencer = core.gui_step_sequencer;
pub const gui_file_drop = core.gui_file_drop;
pub const gui_file_importer = core.gui_file_importer;
pub const gui_audio_file_importer = core.gui_audio_file_importer;
pub const gui_audio_sample_store = core.gui_audio_sample_store;
pub const gui_sample_player = core.gui_sample_player;
pub const gui_ir_convolution = core.gui_ir_convolution;
pub const gui_ir_editor = core.gui_ir_editor;
pub const gui_progress = core.gui_progress;
pub const gui_range_selection = core.gui_range_selection;
pub const gui_viewport = core.gui_viewport;
pub const parameters = core.parameters;
pub const realtime_audit = core.realtime_audit;
pub const lv2 = core.lv2;
pub const dsp = core.dsp;
pub const resource = core.resource;
pub const plugin = core.plugin;
pub const process = core.process;
pub const state = core.state;
pub const units = core.units;
pub const version = "0.2.1-dev";
pub const HostRequestSink = core.plugin.HostRequestSink;
pub const HostChange = core.plugin.HostChange;
pub const vst3_adapter = vst3_adapter_mod;
pub const Vst3Processor = vst3_adapter_mod.Processor;
pub const Vst3ProcessorWithParameters =
    vst3_adapter_mod.ProcessorWithParameters;
pub const Vst3Effect =
    vst3.zig_vst3_plugin_effect.HighLevelEffect;
pub const Vst3EffectWithParameters =
    vst3.zig_vst3_plugin_effect.HighLevelEffectWithParameters;
pub const Vst3Controller =
    vst3.zig_vst3_plugin_effect.HighLevelEditController;
pub const Vst3ControllerWithParameters =
    vst3.zig_vst3_plugin_effect
        .HighLevelEditControllerWithParameters;

pub fn backendVersion() []const u8 {
    return vst3.version;
}

test "zig-vst3-plugin sees zig-vst3" {
    try std.testing.expectEqualStrings("0.2.1-dev", backendVersion());
}

test "zig-vst3-plugin exposes the VST3 runtime adapter" {
    try std.testing.expect(@hasDecl(@This(), "Vst3Processor"));
    try std.testing.expect(@hasDecl(@This(), "Vst3Effect"));
    try std.testing.expect(@hasDecl(@This(), "Vst3Controller"));
    std.testing.refAllDecls(vst3_adapter_mod);
}

test "zig-vst3-plugin re-exports core modules" {
    try std.testing.expect(@hasDecl(parameters, "FloatParam"));
    try std.testing.expect(@hasDecl(realtime_audit, "Scope"));
    try std.testing.expect(@hasDecl(parameters, "LogFloatParam"));
    try std.testing.expect(@hasDecl(dsp, "SmoothedBiquad"));
    try std.testing.expect(@hasDecl(dsp, "DenormalScope"));
    try std.testing.expect(@hasDecl(dsp, "StreamingResampler"));
    try std.testing.expect(@hasDecl(dsp, "FixedRatePipeline"));
    try std.testing.expect(@hasDecl(dsp, "BlockProcessor"));
    try std.testing.expect(@hasDecl(dsp, "Oscillator"));
    try std.testing.expect(@hasDecl(dsp, "Compressor"));
    try std.testing.expect(@hasDecl(dsp, "NoiseGate"));
    try std.testing.expect(@hasDecl(dsp, "Limiter"));
    try std.testing.expect(@hasDecl(dsp, "DelayLine"));
    try std.testing.expect(@hasDecl(dsp, "StereoPanner"));
    try std.testing.expect(@hasDecl(dsp, "PartitionedConvolver"));
    try std.testing.expect(@hasDecl(dsp, "Fft"));
    try std.testing.expect(@hasDecl(dsp, "FirFilter"));
    try std.testing.expect(@hasDecl(dsp, "FirDesigner"));
    try std.testing.expect(@hasDecl(dsp, "FirLeastSquaresBand"));
    try std.testing.expect(@hasDecl(dsp, "FirEquirippleDesigner"));
    try std.testing.expect(@hasDecl(dsp, "FirEquirippleSymmetry"));
    try std.testing.expect(@hasDecl(dsp, "PolyphaseFirBank"));
    try std.testing.expect(@hasDecl(dsp, "Oversampler"));
    try std.testing.expect(@hasDecl(dsp, "DryWetMixer"));
    try std.testing.expect(@hasDecl(dsp, "WaveShaper"));
    try std.testing.expect(@hasDecl(dsp, "Chorus"));
    try std.testing.expect(@hasDecl(dsp, "Phaser"));
    try std.testing.expect(@hasDecl(dsp, "StateVariableFilter"));
    try std.testing.expect(@hasDecl(dsp, "LinkwitzRileyFilter"));
    try std.testing.expect(@hasDecl(dsp, "Reverb"));
    try std.testing.expect(@hasDecl(dsp, "LookupTable"));
    try std.testing.expect(@hasDecl(dsp, "ProcessorChain"));
    try std.testing.expect(@hasDecl(dsp, "FirstOrderTptFilter"));
    try std.testing.expect(@hasDecl(dsp, "BallisticsFilter"));
    try std.testing.expect(@hasDecl(dsp, "LogRampedValue"));
    try std.testing.expect(@hasDecl(dsp, "Gain"));
    try std.testing.expect(@hasDecl(dsp, "Bias"));
    try std.testing.expect(@hasDecl(dsp, "PannerRule"));
    try std.testing.expect(@hasDecl(dsp, "ProcessorDuplicator"));
    try std.testing.expect(@hasDecl(dsp, "AudioBlock"));
    try std.testing.expect(@hasDecl(dsp, "AudioMetadataEntry"));
    try std.testing.expect(@hasDecl(dsp, "ConstAudioBlock"));
    try std.testing.expect(@hasDecl(dsp, "requiredAiffBytes"));
    try std.testing.expect(@hasDecl(dsp, "writeInterleavedAiff"));
    try std.testing.expect(@hasDecl(dsp, "AiffFileWriter"));
    try std.testing.expect(@hasDecl(dsp, "AiffWriter"));
    try std.testing.expect(@hasDecl(dsp, "FlacCommentIterator"));
    try std.testing.expect(@hasDecl(dsp, "FlacFileReader"));
    try std.testing.expect(@hasDecl(dsp, "FlacFileWriter"));
    try std.testing.expect(@hasDecl(dsp, "FlacFileWriterMetadata"));
    try std.testing.expect(@hasDecl(dsp, "OggFilePacketReader"));
    try std.testing.expect(@hasDecl(dsp, "OggStreamWriter"));
    try std.testing.expect(@hasDecl(dsp, "VorbisIdentification"));
    try std.testing.expect(@hasDecl(dsp, "decodeInterleavedFlac"));
    try std.testing.expect(@hasDecl(dsp, "encodeInterleavedFlac"));
    try std.testing.expect(
        @hasDecl(dsp, "encodeInterleavedFlacWithComments"),
    );
    try std.testing.expect(@hasDecl(dsp, "FlacSeekTableIterator"));
    try std.testing.expect(
        @hasDecl(dsp, "encodeInterleavedFlacWithSeekTable"),
    );
    try std.testing.expect(@hasDecl(dsp, "decodeInterleavedFlacRange"));
    try std.testing.expect(
        @hasDecl(dsp, "requiredFlacCommentMetadataBytes"),
    );
    try std.testing.expect(
        @hasDecl(dsp, "requiredFlacFrameStorageBytes"),
    );
    try std.testing.expect(
        @hasDecl(dsp, "requiredFlacFileWriterMetadataBytes"),
    );
    try std.testing.expect(@hasDecl(dsp, "requiredFlacPendingSamples"));
    try std.testing.expect(
        @hasDecl(dsp, "decodeInterleavedFlacWithWideScratch"),
    );
    try std.testing.expect(@hasDecl(dsp, "ProcessSpec"));
    try std.testing.expect(@hasDecl(dsp, "ProcessContextReplacing"));
    try std.testing.expect(@hasDecl(dsp, "ProcessContextNonReplacing"));
    try std.testing.expect(@hasDecl(plugin, "ProcessorRuntime"));
    try std.testing.expect(@hasDecl(plugin, "OfflineRenderer"));
    try std.testing.expect(@hasDecl(plugin, "StandaloneRuntime"));
    try std.testing.expect(@hasDecl(plugin, "StandaloneApplication"));
    try std.testing.expect(@hasDecl(plugin, "AudioDevice"));
    try std.testing.expect(@hasDecl(plugin, "DeviceAudioBlock"));
    try std.testing.expect(@hasDecl(plugin, "DeviceChannelRouter"));
    try std.testing.expect(@hasDecl(plugin, "DeviceChannelRouting"));
    try std.testing.expect(@hasDecl(plugin, "DeviceCatalog"));
    try std.testing.expect(@hasDecl(plugin, "DeviceSelection"));
    try std.testing.expect(@hasDecl(plugin, "DeviceSelectionTracker"));
    try std.testing.expect(@hasDecl(plugin, "Midi1InputDevice"));
    try std.testing.expect(@hasDecl(plugin, "Midi1InputQueue"));
    try std.testing.expect(@hasDecl(plugin, "Midi1BlockScheduler"));
    try std.testing.expect(@hasDecl(plugin, "UmpInputDevice"));
    try std.testing.expect(@hasDecl(plugin, "UmpInputQueue"));
    try std.testing.expect(@hasDecl(plugin, "UmpBlockScheduler"));
    try std.testing.expect(@hasDecl(dsp, "Matrix"));
    try std.testing.expect(@hasDecl(dsp, "DynamicMatrix"));
    try std.testing.expect(@hasDecl(dsp, "HrtfMotionRenderer"));
    try std.testing.expect(@hasDecl(dsp, "HrtfMotionClock"));
    try std.testing.expect(@hasDecl(dsp, "HrtfMotionPointQueue"));
    try std.testing.expect(@hasDecl(dsp, "HrtfSofaLoader"));
    try std.testing.expect(@hasDecl(dsp, "HrtfMotionPoint"));
    try std.testing.expect(
        @hasDecl(dsp, "DynamicLuDecomposition"),
    );
    try std.testing.expect(
        @hasDecl(dsp, "DynamicQrDecomposition"),
    );
    try std.testing.expect(
        @hasDecl(dsp, "DynamicSvdDecomposition"),
    );
    try std.testing.expect(@hasDecl(dsp, "Polynomial"));
    try std.testing.expect(@hasDecl(dsp, "LadderFilter"));
    try std.testing.expect(@hasDecl(dsp, "Phase"));
    try std.testing.expect(@hasDecl(dsp, "besselI0"));
    try std.testing.expect(@hasDecl(dsp, "ellipticIntegralK"));
    try std.testing.expect(@hasDecl(dsp, "ellipticIntegralF"));
    try std.testing.expect(@hasDecl(dsp, "jacobiElliptic"));
    try std.testing.expect(@hasDecl(dsp, "inverseJacobiSn"));
    try std.testing.expect(@hasDecl(dsp, "inverseJacobiCn"));
    try std.testing.expect(@hasDecl(dsp, "inverseJacobiDn"));
    try std.testing.expect(@hasDecl(dsp, "ButterworthDesigner"));
    try std.testing.expect(@hasDecl(dsp, "ButterworthCascade"));
    try std.testing.expect(@hasDecl(dsp, "ButterworthSpecification"));
    try std.testing.expect(
        @hasDecl(dsp, "ButterworthSpecificationDesign"),
    );
    try std.testing.expect(@hasDecl(dsp, "ChebyshevDesigner"));
    try std.testing.expect(@hasDecl(dsp, "ChebyshevSpecification"));
    try std.testing.expect(@hasDecl(dsp, "ChebyshevTypeIIDesigner"));
    try std.testing.expect(
        @hasDecl(dsp, "ChebyshevTypeIISpecificationDesign"),
    );
    try std.testing.expect(@hasDecl(dsp, "EllipticDesigner"));
    try std.testing.expect(@hasDecl(dsp, "Flanger"));
    try std.testing.expect(@hasDecl(dsp, "Vibrato"));
    try std.testing.expect(@hasDecl(dsp, "ModulationNoteDivision"));
    try std.testing.expect(@hasDecl(dsp, "ModulationRateSmoother"));
    try std.testing.expect(@hasDecl(dsp, "modulationRateHz"));
    try std.testing.expect(@hasDecl(dsp, "FastMathApproximations"));
    try std.testing.expect(@hasDecl(dsp, "FastMathOperation"));
    try std.testing.expect(@hasDecl(dsp, "StereoModulation"));
    try std.testing.expect(@hasDecl(dsp, "SimdRegister"));
    try std.testing.expect(@hasDecl(dsp, "NativeSimdRegister"));
    try std.testing.expect(@hasDecl(dsp, "ComplexSimdRegister"));
    try std.testing.expect(@hasDecl(dsp, "KernelDispatcher"));
    try std.testing.expect(@hasDecl(dsp, "InterSampleLimiter"));
    try std.testing.expect(@hasDecl(dsp, "LookaheadLimiter"));
    try std.testing.expect(@hasDecl(dsp, "TwoBandCompressor"));
    try std.testing.expect(@hasDecl(dsp, "LinearSmoothedValue"));
    try std.testing.expect(@hasDecl(dsp, "MultiplicativeSmoothedValue"));
    try std.testing.expect(@hasDecl(dsp, "SharedProcessorDuplicator"));
    try std.testing.expect(@hasDecl(dsp, "RealtimeSnapshotPublisher"));
    try std.testing.expect(@hasDecl(dsp, "RealtimeReferencePublisher"));
    try std.testing.expect(@hasDecl(dsp, "PolyphaseAllpassDesigner"));
    try std.testing.expect(
        @hasDecl(dsp, "PolyphaseAllpassHalfBandFilter"),
    );
    try std.testing.expect(@hasDecl(dsp, "PolyphaseIirOversampler"));
    try std.testing.expect(
        @hasDecl(dsp, "PolyphaseIirOversamplingOptions"),
    );
    try std.testing.expect(
        @hasDecl(dsp, "MultichannelPolyphaseIirOversampler"),
    );
    try std.testing.expect(@hasDecl(dsp, "Rf64FileWriter"));
    try std.testing.expect(@hasDecl(dsp, "MultichannelOversampler"));
    try std.testing.expect(@hasDecl(dsp, "requiredWavBytes"));
    try std.testing.expect(@hasDecl(dsp, "writeInterleavedWav"));
    try std.testing.expect(@hasDecl(dsp, "WavWriter"));
    try std.testing.expect(@hasDecl(dsp, "WavFileWriter"));
    try std.testing.expect(@hasDecl(dsp, "Wave64FileWriter"));
    try std.testing.expect(@hasDecl(dsp, "fillWindow"));
    try std.testing.expect(@hasDecl(dsp, "applyWindow"));
    try std.testing.expect(@hasDecl(dsp, "fillKaiserWindow"));
    try std.testing.expect(@hasDecl(dsp, "applyKaiserWindow"));
    try std.testing.expect(@hasDecl(resource.job, "Job"));
    try std.testing.expect(@hasDecl(resource.exchange, "Exchange"));
    try std.testing.expect(@hasDecl(resource, "Reference"));
    try std.testing.expect(@hasDecl(resource, "ResourceRecovery"));
    try std.testing.expect(@hasDecl(parameters, "normalizedFromBipolar"));
    try std.testing.expect(@hasDecl(plugin, "PluginSpec"));
    try std.testing.expect(@hasDecl(process, "ProcessContext"));
    try std.testing.expect(@hasDecl(process, "ProcessMode"));
    try std.testing.expect(@hasDecl(process, "Transport"));
    try std.testing.expect(@hasDecl(process, "Midi1Message"));
    try std.testing.expect(@hasDecl(process, "Midi1StreamDecoder"));
    try std.testing.expect(@hasDecl(process, "MidiRpnDecoder"));
    try std.testing.expect(@hasDecl(process, "MidiSystemMessage"));
    try std.testing.expect(@hasDecl(process, "MidiUtilityMessage"));
    try std.testing.expect(@hasDecl(process, "UmpPacket"));
    try std.testing.expect(@hasDecl(process, "UmpIterator"));
    try std.testing.expect(@hasDecl(process, "Midi2ChannelMessage"));
    try std.testing.expect(@hasDecl(process, "Sysex7Packetizer"));
    try std.testing.expect(@hasDecl(process, "Sysex7Reassembler"));
    try std.testing.expect(@hasDecl(process, "Sysex8Reassembler"));
    try std.testing.expect(@hasDecl(process, "MidiStreamMessage"));
    try std.testing.expect(@hasDecl(process, "MidiStreamTextReassembler"));
    try std.testing.expect(@hasDecl(process, "MidiFile"));
    try std.testing.expect(@hasDecl(process, "MidiFileWriter"));
    try std.testing.expect(@hasDecl(process, "MpeZoneLayout"));
    try std.testing.expect(@hasDecl(process, "MpeZoneSynchronizer"));
    try std.testing.expect(@hasDecl(process, "MpeInstrument"));
    try std.testing.expect(@hasDecl(process, "MpeMemberChannelAllocator"));
    try std.testing.expect(@hasDecl(state, "writeParameterState"));
    try std.testing.expect(@hasDecl(state, "format_version"));
    try std.testing.expect(@hasDecl(units, "UnitSet"));
    try std.testing.expect(@hasDecl(gui, "Editor"));
    try std.testing.expect(@hasDecl(editor_state, "Store"));
    try std.testing.expect(@hasDecl(gui_preset_browser, "Browser"));
    try std.testing.expect(@hasDecl(gui_telemetry, "ScalarSnapshot"));
    try std.testing.expect(@hasDecl(gui_graph, "SnapshotSeries"));
    try std.testing.expect(@hasDecl(gui_graph, "WaveformCapture"));
    try std.testing.expect(@hasDecl(gui_graph, "SpectrumAnalyzer"));
    try std.testing.expect(@hasDecl(gui_piano, "Keyboard"));
    try std.testing.expect(@hasDecl(gui_step_sequencer, "Sequencer"));
    try std.testing.expect(@hasDecl(gui_file_drop, "DropZone"));
    try std.testing.expect(@hasDecl(gui_file_importer, "Model"));
    try std.testing.expect(@hasDecl(gui_audio_file_importer, "Importer"));
    try std.testing.expect(@hasDecl(gui_audio_sample_store, "Store"));
    try std.testing.expect(@hasDecl(gui_sample_player, "Player"));
    try std.testing.expect(@hasDecl(gui_ir_convolution, "PartitionedConvolver"));
    try std.testing.expect(@hasDecl(gui_ir_editor, "Editor"));
    try std.testing.expect(@hasDecl(gui_progress, "Snapshot"));
    try std.testing.expect(@hasDecl(gui_range_selection, "State"));
    try std.testing.expect(@hasDecl(gui_viewport, "State"));
    try std.testing.expect(@hasDecl(vst3.zig_vst3_plugin_effect, "HostRequestSink"));
}

test "zig-vst3-plugin runs core module tests" {
    std.testing.refAllDecls(core);
}
