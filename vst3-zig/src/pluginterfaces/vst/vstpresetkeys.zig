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

pub const MusicalCharacter = struct {
    pub const kMono: vsttypes.CString = "Mono";
    pub const kPoly: vsttypes.CString = "Poly";
    pub const kSplit: vsttypes.CString = "Split";
    pub const kLayer: vsttypes.CString = "Layer";
    pub const kGlide: vsttypes.CString = "Glide";
    pub const kGlissando: vsttypes.CString = "Glissando";
    pub const kMajor: vsttypes.CString = "Major";
    pub const kMinor: vsttypes.CString = "Minor";
    pub const kSingle: vsttypes.CString = "Single";
    pub const kEnsemble: vsttypes.CString = "Ensemble";
    pub const kAcoustic: vsttypes.CString = "Acoustic";
    pub const kElectric: vsttypes.CString = "Electric";
    pub const kAnalog: vsttypes.CString = "Analog";
    pub const kDigital: vsttypes.CString = "Digital";
    pub const kVintage: vsttypes.CString = "Vintage";
    pub const kModern: vsttypes.CString = "Modern";
    pub const kOld: vsttypes.CString = "Old";
    pub const kNew: vsttypes.CString = "New";
    pub const kClean: vsttypes.CString = "Clean";
    pub const kDistorted: vsttypes.CString = "Distorted";
    pub const kDry: vsttypes.CString = "Dry";
    pub const kProcessed: vsttypes.CString = "Processed";
    pub const kHarmonic: vsttypes.CString = "Harmonic";
    pub const kDissonant: vsttypes.CString = "Dissonant";
    pub const kClear: vsttypes.CString = "Clear";
    pub const kNoisy: vsttypes.CString = "Noisy";
    pub const kThin: vsttypes.CString = "Thin";
    pub const kRich: vsttypes.CString = "Rich";
    pub const kDark: vsttypes.CString = "Dark";
    pub const kBright: vsttypes.CString = "Bright";
    pub const kCold: vsttypes.CString = "Cold";
    pub const kWarm: vsttypes.CString = "Warm";
    pub const kMetallic: vsttypes.CString = "Metallic";
    pub const kWooden: vsttypes.CString = "Wooden";
    pub const kGlass: vsttypes.CString = "Glass";
    pub const kPlastic: vsttypes.CString = "Plastic";
    pub const kPercussive: vsttypes.CString = "Percussive";
    pub const kSoft: vsttypes.CString = "Soft";
    pub const kFast: vsttypes.CString = "Fast";
    pub const kSlow: vsttypes.CString = "Slow";
    pub const kShort: vsttypes.CString = "Short";
    pub const kLong: vsttypes.CString = "Long";
    pub const kAttack: vsttypes.CString = "Attack";
    pub const kRelease: vsttypes.CString = "Release";
    pub const kDecay: vsttypes.CString = "Decay";
    pub const kSustain: vsttypes.CString = "Sustain";
    pub const kFastAttack: vsttypes.CString = "Fast Attack";
    pub const kSlowAttack: vsttypes.CString = "Slow Attack";
    pub const kShortRelease: vsttypes.CString = "Short Release";
    pub const kLongRelease: vsttypes.CString = "Long Release";
    pub const kStatic: vsttypes.CString = "Static";
    pub const kMoving: vsttypes.CString = "Moving";
    pub const kLoop: vsttypes.CString = "Loop";
    pub const kOneShot: vsttypes.CString = "One Shot";
};

test "preset attributes expose SDK strings" {
    try @import("std").testing.expectEqualStrings("PlugInName", PresetAttributes.kPlugInName);
    try @import("std").testing.expectEqualStrings("StateType", PresetAttributes.kStateType);
    try @import("std").testing.expectEqualStrings("TrackPreset", StateType.kTrackPreset);
    try @import("std").testing.expectEqualStrings("One Shot", MusicalCharacter.kOneShot);
}
