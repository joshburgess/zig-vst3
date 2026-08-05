const base_types = @import("../base/types.zig");
const ibstream = @import("../base/ibstream.zig");
const tuid = @import("../../tuid.zig");

pub const ixml_representation_controller_iid = tuid.inlineUid(0xA81A0471, 0x48C34DC4, 0xAC30C9E1, 0x3C8393D5);

pub const RepresentationInfo = extern struct {
    vendor: [64]base_types.char8 = [_]base_types.char8{0} ** 64,
    name: [64]base_types.char8 = [_]base_types.char8{0} ** 64,
    version: [64]base_types.char8 = [_]base_types.char8{0} ** 64,
    host: [64]base_types.char8 = [_]base_types.char8{0} ** 64,

    pub const kNameSize = 64;
};

pub const kNameSize = RepresentationInfo.kNameSize;

pub const IXmlRepresentationControllerVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    getXmlRepresentationStream: *const fn (*anyopaque, [*c]RepresentationInfo, ?*ibstream.IBStream) callconv(.c) base_types.tresult,
};

pub const IXmlRepresentationController = extern struct {
    vtable: *const IXmlRepresentationControllerVTable,
};

pub const Tags = struct {
    pub const rootXml = "vstXML";
    pub const comment = "comment";
    pub const cell = "cell";
    pub const cellGroup = "cellGroup";
    pub const cellGroupTemplate = "cellGroupTemplate";
    pub const curve = "curve";
    pub const curveTemplate = "curveTemplate";
    pub const date = "date";
    pub const layer = "layer";
    pub const name = "name";
    pub const originator = "originator";
    pub const page = "page";
    pub const pageTemplate = "pageTemplate";
    pub const plugin = "plugin";
    pub const value = "value";
    pub const valueDisplay = "valueDisplay";
    pub const valueList = "valueList";
    pub const representation = "representation";
    pub const segment = "segment";
    pub const segmentList = "segmentList";
    pub const titleDisplay = "titleDisplay";
};

pub const Attributes = struct {
    pub const category = "category";
    pub const classID = "classID";
    pub const endPoint = "endPoint";
    pub const index = "index";
    pub const flags = "flags";
    pub const function = "function";
    pub const host = "host";
    pub const ledStyle = "ledStyle";
    pub const length = "length";
    pub const linkedTo = "linkedTo";
    pub const name = "name";
    pub const order = "order";
    pub const page = "page";
    pub const parameterID = "parameterID";
    pub const startPoint = "startPoint";
    pub const style = "style";
    pub const switchStyle = "switchStyle";
    pub const template = "template";
    pub const turnsPerFullRange = "turnsPerFullRange";
    pub const @"type" = "type";
    pub const unitID = "unitID";
    pub const variables = "variables";
    pub const vendor = "vendor";
    pub const version = "version";

    pub const kStyle = style;
    pub const kLEDStyle = ledStyle;
    pub const kSwitchStyle = switchStyle;
    pub const kKnobTurnsPerFullRange = turnsPerFullRange;
    pub const kFunction = function;
    pub const kFlags = flags;
};

pub const RemoteNames = struct {
    pub const generic = "Generic";
    pub const generic4Cells = "Generic 4 Cells";
    pub const generic8Cells = "Generic 8 Cells";
    pub const generic12Cells = "Generic 12 Cells";
    pub const generic24Cells = "Generic 24 Cells";
    pub const genericNCells = "Generic %d Cells";
    pub const quickControl8Cells = "Quick Controls 8 Cells";
};

pub const LayerType = enum(base_types.int32) {
    kKnob = 0,
    kPressedKnob = 1,
    kSwitchKnob = 2,
    kSwitch = 3,
    kLED = 4,
    kLink = 5,
    kDisplay = 6,
    kFader = 7,
    kEndOfLayerType = 8,

    pub const fidStrings = [_]?base_types.FIDString{
        "knob",
        "pressedKnob",
        "switchKnob",
        "switch",
        "LED",
        "link",
        "display",
        "fader",
        null,
    };
};

pub const CurveType = struct {
    pub const kSegment = "segment";
    pub const kValueList = "valueList";
};

pub const AttributesFunction = struct {
    pub const kPanPosCenterXFunc = "PanPosCenterX";
    pub const kPanPosCenterYFunc = "PanPosCenterY";
    pub const kPanPosFrontLeftXFunc = "PanPosFrontLeftX";
    pub const kPanPosFrontLeftYFunc = "PanPosFrontLeftY";
    pub const kPanPosFrontRightXFunc = "PanPosFrontRightX";
    pub const kPanPosFrontRightYFunc = "PanPosFrontRightY";
    pub const kPanRotationFunc = "PanRotation";
    pub const kPanLawFunc = "PanLaw";
    pub const kPanMirrorModeFunc = "PanMirrorMode";
    pub const kPanLfeGainFunc = "PanLfeGain";
    pub const kGainReductionFunc = "GainReduction";
    pub const kSoloFunc = "Solo";
    pub const kMuteFunc = "Mute";
    pub const kVolumeFunc = "Volume";
};

pub const AttributesStyle = struct {
    pub const kInverseStyle = "inverse";
    pub const kLEDWrapLeftStyle = "wrapLeft";
    pub const kLEDWrapRightStyle = "wrapRight";
    pub const kLEDSpreadStyle = "spread";
    pub const kLEDBoostCutStyle = "boostCut";
    pub const kLEDSingleDotStyle = "singleDot";
    pub const kSwitchPushStyle = "push";
    pub const kSwitchPushIncLoopedStyle = "pushIncLooped";
    pub const kSwitchPushDecLoopedStyle = "pushDecLooped";
    pub const kSwitchPushIncStyle = "pushInc";
    pub const kSwitchPushDecStyle = "pushDec";
    pub const kSwitchLatchStyle = "latch";
};

pub const AttributesFlags = struct {
    pub const kHideableFlag = "hideable";
};

test "representation struct sizes match SDK layout" {
    try @import("std").testing.expectEqual(@as(usize, 256), @sizeOf(RepresentationInfo));
    try @import("std").testing.expectEqual(@as(usize, 1), @alignOf(RepresentationInfo));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IXmlRepresentationController));
    try @import("std").testing.expectEqual(@as(usize, 4), @typeInfo(IXmlRepresentationControllerVTable).@"struct".fields.len);
}
