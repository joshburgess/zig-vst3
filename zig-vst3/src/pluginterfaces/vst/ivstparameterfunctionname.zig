const base_types = @import("../base/types.zig");
const tuid = @import("../../tuid.zig");
const vsttypes = @import("vsttypes.zig");

pub const iparameter_function_name_iid = tuid.inlineUid(0x6D21E1DC, 0x91199D4B, 0xA2A02FEF, 0x6C1AE55C);

pub const FunctionNameType = struct {
    pub const kCompGainReduction: vsttypes.CString = "Comp:GainReduction";
    pub const kCompGainReductionMax: vsttypes.CString = "Comp:GainReductionMax";
    pub const kCompGainReductionPeakHold: vsttypes.CString = "Comp:GainReductionPeakHold";
    pub const kCompResetGainReductionMax: vsttypes.CString = "Comp:ResetGainReductionMax";
    pub const kLowLatencyMode: vsttypes.CString = "LowLatencyMode";
    pub const kDryWetMix: vsttypes.CString = "DryWetMix";
    pub const kRandomize: vsttypes.CString = "Randomize";
    pub const kPanPosCenterX: vsttypes.CString = "PanPosCenterX";
    pub const kPanPosCenterY: vsttypes.CString = "PanPosCenterY";
    pub const kPanPosCenterZ: vsttypes.CString = "PanPosCenterZ";
};

pub const IParameterFunctionNameVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    getParameterIDFromFunctionName: *const fn (*anyopaque, vsttypes.UnitID, ?base_types.FIDString, [*c]vsttypes.ParamID) callconv(.c) base_types.tresult,
};

pub const IParameterFunctionName = extern struct {
    vtable: *const IParameterFunctionNameVTable,
};

test "parameter function name vtable slot count includes FUnknown prefix" {
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IParameterFunctionName));
    try @import("std").testing.expectEqual(@as(usize, 4), @typeInfo(IParameterFunctionNameVTable).@"struct".fields.len);
}
