const vsttypes = @import("vsttypes.zig");

pub const PresetAttributes = struct {
    pub const kPlugInName: vsttypes.CString = "PlugInName";
    pub const kPlugInCategory: vsttypes.CString = "PlugInCategory";
    pub const kInstrument: vsttypes.CString = "MusicalInstrument";
    pub const kStyle: vsttypes.CString = "MusicalStyle";
    pub const kCharacter: vsttypes.CString = "MusicalCharacter";
    pub const kStateType: vsttypes.CString = "StateType";
    pub const kFilePathStringType: vsttypes.CString = "FilePathString";
    pub const kName: vsttypes.CString = "Name";
    pub const kFileName: vsttypes.CString = "FileName";
};

pub const StateType = struct {
    pub const kProject: vsttypes.CString = "Project";
    pub const kDefault: vsttypes.CString = "Default";
    pub const kTrackPreset: vsttypes.CString = "TrackPreset";
};

test "preset attributes expose SDK strings" {
    try @import("std").testing.expectEqualStrings("PlugInName", PresetAttributes.kPlugInName);
    try @import("std").testing.expectEqualStrings("StateType", PresetAttributes.kStateType);
    try @import("std").testing.expectEqualStrings("TrackPreset", StateType.kTrackPreset);
}
