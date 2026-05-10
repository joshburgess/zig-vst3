const std = @import("std");
const process_context = @import("zig-vst3").pluginterfaces.vst.ivstprocesscontext;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("FrameRate.kPullDownRate {}\n", .{process_context.FrameRateFlags.kPullDownRate});
    try stdout.print("FrameRate.kDropRate {}\n", .{process_context.FrameRateFlags.kDropRate});
    try stdout.print("Chord.kChordMask {}\n", .{process_context.ChordMasks.kChordMask});
    try stdout.print("Chord.kReservedMask {}\n", .{process_context.ChordMasks.kReservedMask});
    try stdout.print("ProcessContext.kPlaying {}\n", .{process_context.StatesAndFlags.kPlaying});
    try stdout.print("ProcessContext.kCycleActive {}\n", .{process_context.StatesAndFlags.kCycleActive});
    try stdout.print("ProcessContext.kRecording {}\n", .{process_context.StatesAndFlags.kRecording});
    try stdout.print("ProcessContext.kSystemTimeValid {}\n", .{process_context.StatesAndFlags.kSystemTimeValid});
    try stdout.print("ProcessContext.kContTimeValid {}\n", .{process_context.StatesAndFlags.kContTimeValid});
    try stdout.print("ProcessContext.kProjectTimeMusicValid {}\n", .{process_context.StatesAndFlags.kProjectTimeMusicValid});
    try stdout.print("ProcessContext.kBarPositionValid {}\n", .{process_context.StatesAndFlags.kBarPositionValid});
    try stdout.print("ProcessContext.kCycleValid {}\n", .{process_context.StatesAndFlags.kCycleValid});
    try stdout.print("ProcessContext.kTempoValid {}\n", .{process_context.StatesAndFlags.kTempoValid});
    try stdout.print("ProcessContext.kTimeSigValid {}\n", .{process_context.StatesAndFlags.kTimeSigValid});
    try stdout.print("ProcessContext.kChordValid {}\n", .{process_context.StatesAndFlags.kChordValid});
    try stdout.print("ProcessContext.kSmpteValid {}\n", .{process_context.StatesAndFlags.kSmpteValid});
    try stdout.print("ProcessContext.kClockValid {}\n", .{process_context.StatesAndFlags.kClockValid});

    try printType(stdout, "FrameRate", process_context.FrameRate);
    try printOffset(stdout, "FrameRate", "framesPerSecond", process_context.FrameRate, "framesPerSecond");
    try printOffset(stdout, "FrameRate", "flags", process_context.FrameRate, "flags");

    try printType(stdout, "Chord", process_context.Chord);
    try printOffset(stdout, "Chord", "keyNote", process_context.Chord, "keyNote");
    try printOffset(stdout, "Chord", "rootNote", process_context.Chord, "rootNote");
    try printOffset(stdout, "Chord", "chordMask", process_context.Chord, "chordMask");

    try printType(stdout, "ProcessContext", process_context.ProcessContext);
    try printOffset(stdout, "ProcessContext", "state", process_context.ProcessContext, "state");
    try printOffset(stdout, "ProcessContext", "sampleRate", process_context.ProcessContext, "sampleRate");
    try printOffset(stdout, "ProcessContext", "projectTimeSamples", process_context.ProcessContext, "projectTimeSamples");
    try printOffset(stdout, "ProcessContext", "systemTime", process_context.ProcessContext, "systemTime");
    try printOffset(stdout, "ProcessContext", "continousTimeSamples", process_context.ProcessContext, "continousTimeSamples");
    try printOffset(stdout, "ProcessContext", "projectTimeMusic", process_context.ProcessContext, "projectTimeMusic");
    try printOffset(stdout, "ProcessContext", "barPositionMusic", process_context.ProcessContext, "barPositionMusic");
    try printOffset(stdout, "ProcessContext", "cycleStartMusic", process_context.ProcessContext, "cycleStartMusic");
    try printOffset(stdout, "ProcessContext", "cycleEndMusic", process_context.ProcessContext, "cycleEndMusic");
    try printOffset(stdout, "ProcessContext", "tempo", process_context.ProcessContext, "tempo");
    try printOffset(stdout, "ProcessContext", "timeSigNumerator", process_context.ProcessContext, "timeSigNumerator");
    try printOffset(stdout, "ProcessContext", "timeSigDenominator", process_context.ProcessContext, "timeSigDenominator");
    try printOffset(stdout, "ProcessContext", "chord", process_context.ProcessContext, "chord");
    try printOffset(stdout, "ProcessContext", "smpteOffsetSubframes", process_context.ProcessContext, "smpteOffsetSubframes");
    try printOffset(stdout, "ProcessContext", "frameRate", process_context.ProcessContext, "frameRate");
    try printOffset(stdout, "ProcessContext", "samplesToNextClock", process_context.ProcessContext, "samplesToNextClock");
}

fn printType(writer: anytype, comptime name: []const u8, comptime Type: type) !void {
    try writer.print("{s} size {} align {}\n", .{ name, @sizeOf(Type), @alignOf(Type) });
}

fn printOffset(writer: anytype, comptime type_name: []const u8, comptime field_label: []const u8, comptime Type: type, comptime field_name: []const u8) !void {
    try writer.print("{s}.{s} offset {}\n", .{ type_name, field_label, @offsetOf(Type, field_name) });
}
