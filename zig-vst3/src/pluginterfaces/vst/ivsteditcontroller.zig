const base_types = @import("../base/types.zig");
const iplugview = @import("../gui/iplugview.zig");
const ibstream = @import("../base/ibstream.zig");
const tuid = @import("../../tuid.zig");
const vsttypes = @import("vsttypes.zig");

pub const icomponent_handler_iid = tuid.inlineUid(0x93A0BEA3, 0x0BD045DB, 0x8E890B0C, 0xC1E46AC6);
pub const icomponent_handler2_iid = tuid.inlineUid(0xF040B4B3, 0xA36045EC, 0xABCDC045, 0xB4D5A2CC);
pub const icomponent_handler_bus_activation_iid = tuid.inlineUid(0x067D02C1, 0x5B4E274D, 0xA92D90FD, 0x6EAF7240);
pub const iprogress_iid = tuid.inlineUid(0x00C9DC5B, 0x9D904254, 0x91A388C8, 0xB4E91B69);
pub const iedit_controller_iid = tuid.inlineUid(0xDCD7BBE3, 0x7742448D, 0xA874AACC, 0x979C759E);
pub const iedit_controller2_iid = tuid.inlineUid(0x7F4EFE59, 0xF3204967, 0xAC27A3AE, 0xAFB63038);
pub const imidi_mapping_iid = tuid.inlineUid(0xDF0FF9F7, 0x49B74669, 0xB63AB732, 0x7ADBF5E5);
pub const iedit_controller_host_editing_iid = tuid.inlineUid(0xC1271208, 0x70594098, 0xB9DD34B3, 0x6BB0195E);
pub const icomponent_handler_system_time_iid = tuid.inlineUid(0xF9E53056, 0xD1554CD5, 0xB7695E1B, 0x7B0F7745);

pub const kVstComponentControllerClass: base_types.FIDString = "Component Controller Class";

pub const ParameterInfo = extern struct {
    id: vsttypes.ParamID = 0,
    title: vsttypes.String128 = [_]vsttypes.TChar{0} ** 128,
    shortTitle: vsttypes.String128 = [_]vsttypes.TChar{0} ** 128,
    units: vsttypes.String128 = [_]vsttypes.TChar{0} ** 128,
    stepCount: base_types.int32 = 0,
    defaultNormalizedValue: vsttypes.ParamValue = 0,
    unitId: vsttypes.UnitID = 0,
    flags: base_types.int32 = 0,

    pub const ParameterFlags = packed struct(base_types.int32) {
        can_automate: bool = false,
        is_read_only: bool = false,
        is_wrap_around: bool = false,
        is_list: bool = false,
        is_hidden: bool = false,
        _: u10 = 0,
        is_program_change: bool = false,
        is_bypass: bool = false,
        __: u15 = 0,

        pub const kNoFlags: base_types.int32 = 0;
        pub const kCanAutomate: base_types.int32 = 1 << 0;
        pub const kIsReadOnly: base_types.int32 = 1 << 1;
        pub const kIsWrapAround: base_types.int32 = 1 << 2;
        pub const kIsList: base_types.int32 = 1 << 3;
        pub const kIsHidden: base_types.int32 = 1 << 4;
        pub const kIsProgramChange: base_types.int32 = 1 << 15;
        pub const kIsBypass: base_types.int32 = 1 << 16;
    };
};

pub const ViewType = struct {
    pub const kEditor: base_types.FIDString = "editor";
};

pub const RestartFlags = packed struct(base_types.int32) {
    reload_component: bool = false,
    io_changed: bool = false,
    param_values_changed: bool = false,
    latency_changed: bool = false,
    param_titles_changed: bool = false,
    midi_cc_assignment_changed: bool = false,
    note_expression_changed: bool = false,
    io_titles_changed: bool = false,
    prefetchable_support_changed: bool = false,
    routing_info_changed: bool = false,
    keyswitch_changed: bool = false,
    param_id_mapping_changed: bool = false,
    _: u20 = 0,

    pub const kReloadComponent: base_types.int32 = 1 << 0;
    pub const kIoChanged: base_types.int32 = 1 << 1;
    pub const kParamValuesChanged: base_types.int32 = 1 << 2;
    pub const kLatencyChanged: base_types.int32 = 1 << 3;
    pub const kParamTitlesChanged: base_types.int32 = 1 << 4;
    pub const kMidiCCAssignmentChanged: base_types.int32 = 1 << 5;
    pub const kNoteExpressionChanged: base_types.int32 = 1 << 6;
    pub const kIoTitlesChanged: base_types.int32 = 1 << 7;
    pub const kPrefetchableSupportChanged: base_types.int32 = 1 << 8;
    pub const kRoutingInfoChanged: base_types.int32 = 1 << 9;
    pub const kKeyswitchChanged: base_types.int32 = 1 << 10;
    pub const kParamIDMappingChanged: base_types.int32 = 1 << 11;
};

pub const IComponentHandlerVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    beginEdit: *const fn (*anyopaque, vsttypes.ParamID) callconv(.c) base_types.tresult,
    performEdit: *const fn (*anyopaque, vsttypes.ParamID, vsttypes.ParamValue) callconv(.c) base_types.tresult,
    endEdit: *const fn (*anyopaque, vsttypes.ParamID) callconv(.c) base_types.tresult,
    restartComponent: *const fn (*anyopaque, base_types.int32) callconv(.c) base_types.tresult,
};

pub const IComponentHandler = extern struct {
    vtable: *const IComponentHandlerVTable,
};

pub const IComponentHandler2VTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    setDirty: *const fn (*anyopaque, base_types.TBool) callconv(.c) base_types.tresult,
    requestOpenEditor: *const fn (*anyopaque, base_types.FIDString) callconv(.c) base_types.tresult,
    startGroupEdit: *const fn (*anyopaque) callconv(.c) base_types.tresult,
    finishGroupEdit: *const fn (*anyopaque) callconv(.c) base_types.tresult,
};

pub const IComponentHandler2 = extern struct {
    vtable: *const IComponentHandler2VTable,
};

pub const IComponentHandlerBusActivationVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    requestBusActivation: *const fn (*anyopaque, vsttypes.MediaType, vsttypes.BusDirection, base_types.int32, base_types.TBool) callconv(.c) base_types.tresult,
};

pub const IComponentHandlerBusActivation = extern struct {
    vtable: *const IComponentHandlerBusActivationVTable,
};

pub const ProgressType = enum(base_types.uint32) {
    AsyncStateRestoration = 0,
    UIBackgroundTask = 1,
};

pub const ProgressID = base_types.uint64;

pub const IProgressVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    start: *const fn (*anyopaque, base_types.uint32, ?[*]const base_types.char16, [*c]ProgressID) callconv(.c) base_types.tresult,
    update: *const fn (*anyopaque, ProgressID, vsttypes.ParamValue) callconv(.c) base_types.tresult,
    finish: *const fn (*anyopaque, ProgressID) callconv(.c) base_types.tresult,
};

pub const IProgress = extern struct {
    vtable: *const IProgressVTable,
};

pub const IEditControllerVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    initialize: *const fn (*anyopaque, ?*anyopaque) callconv(.c) base_types.tresult,
    terminate: *const fn (*anyopaque) callconv(.c) base_types.tresult,
    setComponentState: *const fn (*anyopaque, ?*ibstream.IBStream) callconv(.c) base_types.tresult,
    setState: *const fn (*anyopaque, ?*ibstream.IBStream) callconv(.c) base_types.tresult,
    getState: *const fn (*anyopaque, ?*ibstream.IBStream) callconv(.c) base_types.tresult,
    getParameterCount: *const fn (*anyopaque) callconv(.c) base_types.int32,
    getParameterInfo: *const fn (*anyopaque, base_types.int32, [*c]ParameterInfo) callconv(.c) base_types.tresult,
    getParamStringByValue: *const fn (*anyopaque, vsttypes.ParamID, vsttypes.ParamValue, [*c]vsttypes.TChar) callconv(.c) base_types.tresult,
    getParamValueByString: *const fn (*anyopaque, vsttypes.ParamID, [*c]vsttypes.TChar, [*c]vsttypes.ParamValue) callconv(.c) base_types.tresult,
    normalizedParamToPlain: *const fn (*anyopaque, vsttypes.ParamID, vsttypes.ParamValue) callconv(.c) vsttypes.ParamValue,
    plainParamToNormalized: *const fn (*anyopaque, vsttypes.ParamID, vsttypes.ParamValue) callconv(.c) vsttypes.ParamValue,
    getParamNormalized: *const fn (*anyopaque, vsttypes.ParamID) callconv(.c) vsttypes.ParamValue,
    setParamNormalized: *const fn (*anyopaque, vsttypes.ParamID, vsttypes.ParamValue) callconv(.c) base_types.tresult,
    setComponentHandler: *const fn (*anyopaque, ?*anyopaque) callconv(.c) base_types.tresult,
    createView: *const fn (*anyopaque, ?base_types.FIDString) callconv(.c) ?*iplugview.IPlugView,
};

pub const IEditController = extern struct {
    vtable: *const IEditControllerVTable,
};

pub const KnobMode = base_types.int32;

pub const KnobModes = enum(KnobMode) {
    kCircularMode = 0,
    kRelativCircularMode = 1,
    kLinearMode = 2,
};

pub const IEditController2VTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    setKnobMode: *const fn (*anyopaque, KnobMode) callconv(.c) base_types.tresult,
    openHelp: *const fn (*anyopaque, base_types.TBool) callconv(.c) base_types.tresult,
    openAboutBox: *const fn (*anyopaque, base_types.TBool) callconv(.c) base_types.tresult,
};

pub const IEditController2 = extern struct {
    vtable: *const IEditController2VTable,
};

pub const IMidiMappingVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    getMidiControllerAssignment: *const fn (*anyopaque, base_types.int32, base_types.int16, vsttypes.CtrlNumber, [*c]vsttypes.ParamID) callconv(.c) base_types.tresult,
};

pub const IMidiMapping = extern struct {
    vtable: *const IMidiMappingVTable,
};

pub const IEditControllerHostEditingVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    beginEditFromHost: *const fn (*anyopaque, vsttypes.ParamID) callconv(.c) base_types.tresult,
    endEditFromHost: *const fn (*anyopaque, vsttypes.ParamID) callconv(.c) base_types.tresult,
};

pub const IEditControllerHostEditing = extern struct {
    vtable: *const IEditControllerHostEditingVTable,
};

pub const IComponentHandlerSystemTimeVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    getSystemTime: *const fn (*anyopaque, [*c]base_types.int64) callconv(.c) base_types.tresult,
};

pub const IComponentHandlerSystemTime = extern struct {
    vtable: *const IComponentHandlerSystemTimeVTable,
};

test "edit controller struct sizes match SDK layout" {
    try @import("std").testing.expectEqual(@as(usize, 792), @sizeOf(ParameterInfo));
    try @import("std").testing.expectEqual(@as(usize, 8), @alignOf(ParameterInfo));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IComponentHandler));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IComponentHandler2));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IComponentHandlerBusActivation));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IProgress));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IEditController));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IEditController2));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IMidiMapping));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IEditControllerHostEditing));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IComponentHandlerSystemTime));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IComponentHandler));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IComponentHandler2));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IComponentHandlerBusActivation));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IProgress));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IEditController));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IEditController2));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IMidiMapping));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IEditControllerHostEditing));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IComponentHandlerSystemTime));
    try @import("std").testing.expectEqual(@as(usize, 7), @typeInfo(IComponentHandlerVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 7), @typeInfo(IComponentHandler2VTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 4), @typeInfo(IComponentHandlerBusActivationVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 6), @typeInfo(IProgressVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 18), @typeInfo(IEditControllerVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 6), @typeInfo(IEditController2VTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 4), @typeInfo(IMidiMappingVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 5), @typeInfo(IEditControllerHostEditingVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 4), @typeInfo(IComponentHandlerSystemTimeVTable).@"struct".fields.len);
}
