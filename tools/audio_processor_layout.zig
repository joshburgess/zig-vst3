const std = @import("std");
const audio_processor = @import("vst3-zig").pluginterfaces.vst.ivstaudioprocessor;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("ComponentFlags.kDistributable {}\n", .{audio_processor.ComponentFlags.kDistributable});
    try stdout.print("ComponentFlags.kSimpleModeSupported {}\n", .{audio_processor.ComponentFlags.kSimpleModeSupported});
    try stdout.print("SymbolicSampleSizes.kSample32 {}\n", .{@intFromEnum(audio_processor.SymbolicSampleSizes.kSample32)});
    try stdout.print("SymbolicSampleSizes.kSample64 {}\n", .{@intFromEnum(audio_processor.SymbolicSampleSizes.kSample64)});
    try stdout.print("ProcessModes.kRealtime {}\n", .{@intFromEnum(audio_processor.ProcessModes.kRealtime)});
    try stdout.print("ProcessModes.kPrefetch {}\n", .{@intFromEnum(audio_processor.ProcessModes.kPrefetch)});
    try stdout.print("ProcessModes.kOffline {}\n", .{@intFromEnum(audio_processor.ProcessModes.kOffline)});
    try stdout.print("kNoTail {}\n", .{audio_processor.kNoTail});
    try stdout.print("kInfiniteTail {}\n", .{audio_processor.kInfiniteTail});
    try stdout.print("IProcessContextRequirements.kNeedSystemTime {}\n", .{audio_processor.ProcessContextRequirementFlags.kNeedSystemTime});
    try stdout.print("IProcessContextRequirements.kNeedContinousTimeSamples {}\n", .{audio_processor.ProcessContextRequirementFlags.kNeedContinousTimeSamples});
    try stdout.print("IProcessContextRequirements.kNeedProjectTimeMusic {}\n", .{audio_processor.ProcessContextRequirementFlags.kNeedProjectTimeMusic});
    try stdout.print("IProcessContextRequirements.kNeedBarPositionMusic {}\n", .{audio_processor.ProcessContextRequirementFlags.kNeedBarPositionMusic});
    try stdout.print("IProcessContextRequirements.kNeedCycleMusic {}\n", .{audio_processor.ProcessContextRequirementFlags.kNeedCycleMusic});
    try stdout.print("IProcessContextRequirements.kNeedSamplesToNextClock {}\n", .{audio_processor.ProcessContextRequirementFlags.kNeedSamplesToNextClock});
    try stdout.print("IProcessContextRequirements.kNeedTempo {}\n", .{audio_processor.ProcessContextRequirementFlags.kNeedTempo});
    try stdout.print("IProcessContextRequirements.kNeedTimeSignature {}\n", .{audio_processor.ProcessContextRequirementFlags.kNeedTimeSignature});
    try stdout.print("IProcessContextRequirements.kNeedChord {}\n", .{audio_processor.ProcessContextRequirementFlags.kNeedChord});
    try stdout.print("IProcessContextRequirements.kNeedFrameRate {}\n", .{audio_processor.ProcessContextRequirementFlags.kNeedFrameRate});
    try stdout.print("IProcessContextRequirements.kNeedTransportState {}\n", .{audio_processor.ProcessContextRequirementFlags.kNeedTransportState});

    try printType(stdout, "ProcessSetup", audio_processor.ProcessSetup);
    try printOffset(stdout, "ProcessSetup", "processMode", audio_processor.ProcessSetup, "processMode");
    try printOffset(stdout, "ProcessSetup", "symbolicSampleSize", audio_processor.ProcessSetup, "symbolicSampleSize");
    try printOffset(stdout, "ProcessSetup", "maxSamplesPerBlock", audio_processor.ProcessSetup, "maxSamplesPerBlock");
    try printOffset(stdout, "ProcessSetup", "sampleRate", audio_processor.ProcessSetup, "sampleRate");

    try printType(stdout, "AudioBusBuffers", audio_processor.AudioBusBuffers);
    try printOffset(stdout, "AudioBusBuffers", "numChannels", audio_processor.AudioBusBuffers, "numChannels");
    try printOffset(stdout, "AudioBusBuffers", "silenceFlags", audio_processor.AudioBusBuffers, "silenceFlags");
    try printOffset(stdout, "AudioBusBuffers", "channelBuffers64", audio_processor.AudioBusBuffers, "channelBuffers");

    try printType(stdout, "ProcessData", audio_processor.ProcessData);
    try printOffset(stdout, "ProcessData", "processMode", audio_processor.ProcessData, "processMode");
    try printOffset(stdout, "ProcessData", "symbolicSampleSize", audio_processor.ProcessData, "symbolicSampleSize");
    try printOffset(stdout, "ProcessData", "numSamples", audio_processor.ProcessData, "numSamples");
    try printOffset(stdout, "ProcessData", "numInputs", audio_processor.ProcessData, "numInputs");
    try printOffset(stdout, "ProcessData", "numOutputs", audio_processor.ProcessData, "numOutputs");
    try printOffset(stdout, "ProcessData", "inputs", audio_processor.ProcessData, "inputs");
    try printOffset(stdout, "ProcessData", "outputs", audio_processor.ProcessData, "outputs");
    try printOffset(stdout, "ProcessData", "inputParameterChanges", audio_processor.ProcessData, "inputParameterChanges");
    try printOffset(stdout, "ProcessData", "outputParameterChanges", audio_processor.ProcessData, "outputParameterChanges");
    try printOffset(stdout, "ProcessData", "inputEvents", audio_processor.ProcessData, "inputEvents");
    try printOffset(stdout, "ProcessData", "outputEvents", audio_processor.ProcessData, "outputEvents");
    try printOffset(stdout, "ProcessData", "processContext", audio_processor.ProcessData, "processContext");

    try printTuid(stdout, "IAudioProcessor", audio_processor.iaudio_processor_iid);
    try printTuid(stdout, "IAudioPresentationLatency", audio_processor.iaudio_presentation_latency_iid);
    try printTuid(stdout, "IProcessContextRequirements", audio_processor.iprocess_context_requirements_iid);
}

fn printType(writer: anytype, comptime name: []const u8, comptime Type: type) !void {
    try writer.print("{s} size {} align {}\n", .{ name, @sizeOf(Type), @alignOf(Type) });
}

fn printOffset(writer: anytype, comptime type_name: []const u8, comptime field_label: []const u8, comptime Type: type, comptime field_name: []const u8) !void {
    try writer.print("{s}.{s} offset {}\n", .{ type_name, field_label, @offsetOf(Type, field_name) });
}

fn printTuid(writer: anytype, comptime name: []const u8, bytes: [16]u8) !void {
    try writer.print("{s} iid", .{name});
    for (bytes) |byte| {
        try writer.print(" {X:0>2}", .{byte});
    }
    try writer.writeByte('\n');
}
