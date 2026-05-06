const std = @import("std");
const preset_keys = @import("vst3-zig").pluginterfaces.vst.vstpresetkeys;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("PresetAttributes.kPlugInName {s}\n", .{preset_keys.PresetAttributes.kPlugInName});
    try stdout.print("PresetAttributes.kPlugInCategory {s}\n", .{preset_keys.PresetAttributes.kPlugInCategory});
    try stdout.print("PresetAttributes.kInstrument {s}\n", .{preset_keys.PresetAttributes.kInstrument});
    try stdout.print("PresetAttributes.kStyle {s}\n", .{preset_keys.PresetAttributes.kStyle});
    try stdout.print("PresetAttributes.kCharacter {s}\n", .{preset_keys.PresetAttributes.kCharacter});
    try stdout.print("PresetAttributes.kStateType {s}\n", .{preset_keys.PresetAttributes.kStateType});
    try stdout.print("PresetAttributes.kFilePathStringType {s}\n", .{preset_keys.PresetAttributes.kFilePathStringType});
    try stdout.print("PresetAttributes.kName {s}\n", .{preset_keys.PresetAttributes.kName});
    try stdout.print("PresetAttributes.kFileName {s}\n", .{preset_keys.PresetAttributes.kFileName});
    try stdout.print("StateType.kProject {s}\n", .{preset_keys.StateType.kProject});
    try stdout.print("StateType.kDefault {s}\n", .{preset_keys.StateType.kDefault});
    try stdout.print("StateType.kTrackPreset {s}\n", .{preset_keys.StateType.kTrackPreset});
}
