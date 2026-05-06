const std = @import("std");
const midi = @import("vst3-zig").pluginterfaces.vst.ivstmidicontrollers;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try printController(stdout, "kCtrlBankSelectMSB", midi.kCtrlBankSelectMSB);
    try printController(stdout, "kCtrlModWheel", midi.kCtrlModWheel);
    try printController(stdout, "kCtrlBreath", midi.kCtrlBreath);
    try printController(stdout, "kCtrlFoot", midi.kCtrlFoot);
    try printController(stdout, "kCtrlPortaTime", midi.kCtrlPortaTime);
    try printController(stdout, "kCtrlDataEntryMSB", midi.kCtrlDataEntryMSB);
    try printController(stdout, "kCtrlVolume", midi.kCtrlVolume);
    try printController(stdout, "kCtrlBalance", midi.kCtrlBalance);
    try printController(stdout, "kCtrlPan", midi.kCtrlPan);
    try printController(stdout, "kCtrlExpression", midi.kCtrlExpression);
    try printController(stdout, "kCtrlBankSelectLSB", midi.kCtrlBankSelectLSB);
    try printController(stdout, "kCtrlSustainOnOff", midi.kCtrlSustainOnOff);
    try printController(stdout, "kCtrlSoundVariation", midi.kCtrlSoundVariation);
    try printController(stdout, "kCtrlEff1Depth", midi.kCtrlEff1Depth);
    try printController(stdout, "kCtrlAllSoundsOff", midi.kCtrlAllSoundsOff);
    try printController(stdout, "kAfterTouch", midi.kAfterTouch);
    try printController(stdout, "kPitchBend", midi.kPitchBend);
    try printController(stdout, "kCountCtrlNumber", midi.kCountCtrlNumber);
    try printController(stdout, "kCtrlProgramChange", midi.kCtrlProgramChange);
    try printController(stdout, "kSystemActiveSensing", midi.kSystemActiveSensing);
}

fn printController(writer: anytype, comptime name: []const u8, controller: @TypeOf(midi.kCtrlBankSelectMSB)) !void {
    try writer.print("{s} {}\n", .{ name, controller });
}
