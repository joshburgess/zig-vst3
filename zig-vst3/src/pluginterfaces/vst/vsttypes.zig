const base = @import("../base/types.zig");

pub const TChar = base.char16;
pub const String128 = [128]TChar;
pub const CString = base.FIDString;

pub const MediaType = base.int32;
pub const BusDirection = base.int32;
pub const BusType = base.int32;
pub const IoMode = base.int32;
pub const UnitID = base.int32;

pub const ParamValue = f64;
pub const ParamID = base.uint32;
pub const ProgramListID = base.int32;
pub const CtrlNumber = base.int16;

pub const TQuarterNotes = f64;
pub const TSamples = base.int64;
pub const ColorSpec = base.uint32;

pub const Sample32 = f32;
pub const Sample64 = f64;
pub const SampleRate = f64;

pub const SpeakerArrangement = base.uint64;
pub const Speaker = base.uint64;

pub const kNoParamId: ParamID = 0xFFFFFFFF;
pub const kMinParamId: ParamID = 0;
pub const kMaxParamId: ParamID = 0x7FFFFFFF;

pub const SDKVersionString = "VST 3.8.0";
pub const SDKVersionMajor: base.uint32 = 3;
pub const SDKVersionMinor: base.uint32 = 8;
pub const SDKVersionSub: base.uint32 = 0;
pub const SDKVersion: base.uint32 = (SDKVersionMajor << 16) | (SDKVersionMinor << 8) | SDKVersionSub;
