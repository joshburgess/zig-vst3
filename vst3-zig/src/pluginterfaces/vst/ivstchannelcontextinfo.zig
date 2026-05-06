const attributes = @import("ivstattributes.zig");
const base_types = @import("../base/types.zig");
const tuid = @import("../../tuid.zig");
const vsttypes = @import("vsttypes.zig");

pub const iinfo_listener_iid = tuid.inlineUid(0x0F194781, 0x8D984ADA, 0xBBA0C1EF, 0xC011D8D0);

pub const IInfoListenerVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    setChannelContextInfos: *const fn (*anyopaque, ?*attributes.IAttributeList) callconv(.C) base_types.tresult,
};

pub const IInfoListener = extern struct {
    vtable: *const IInfoListenerVTable,
};

pub const ChannelContext = struct {
    pub const ChannelPluginLocation = enum(base_types.int32) {
        kPreVolumeFader = 0,
        kPostVolumeFader = 1,
        kUsedAsPanner = 2,
    };

    pub const ColorSpec = vsttypes.ColorSpec;
    pub const ColorComponent = base_types.uint8;

    pub fn getBlue(cs: ColorSpec) ColorComponent {
        return @intCast(cs & 0x000000FF);
    }

    pub fn getGreen(cs: ColorSpec) ColorComponent {
        return @intCast((cs >> 8) & 0x000000FF);
    }

    pub fn getRed(cs: ColorSpec) ColorComponent {
        return @intCast((cs >> 16) & 0x000000FF);
    }

    pub fn getAlpha(cs: ColorSpec) ColorComponent {
        return @intCast((cs >> 24) & 0x000000FF);
    }

    pub const kChannelUIDKey: vsttypes.CString = "channel uid";
    pub const kChannelUIDLengthKey: vsttypes.CString = "channel uid length";
    pub const kChannelRuntimeIDKey: vsttypes.CString = "channel runtime id";
    pub const kChannelNameKey: vsttypes.CString = "channel name";
    pub const kChannelNameLengthKey: vsttypes.CString = "channel name length";
    pub const kChannelColorKey: vsttypes.CString = "channel color";
    pub const kChannelIndexKey: vsttypes.CString = "channel index";
    pub const kChannelIndexNamespaceOrderKey: vsttypes.CString = "channel index namespace order";
    pub const kChannelIndexNamespaceKey: vsttypes.CString = "channel index namespace";
    pub const kChannelIndexNamespaceLengthKey: vsttypes.CString = "channel index namespace length";
    pub const kChannelImageKey: vsttypes.CString = "channel image";
    pub const kChannelPluginLocationKey: vsttypes.CString = "channel plugin location";
};

test "channel context vtable slot count includes FUnknown prefix" {
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IInfoListener));
    try @import("std").testing.expectEqual(@as(usize, 4), @typeInfo(IInfoListenerVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(base_types.uint8, 0x44), ChannelContext.getBlue(0x11223344));
    try @import("std").testing.expectEqual(@as(base_types.uint8, 0x33), ChannelContext.getGreen(0x11223344));
    try @import("std").testing.expectEqual(@as(base_types.uint8, 0x22), ChannelContext.getRed(0x11223344));
    try @import("std").testing.expectEqual(@as(base_types.uint8, 0x11), ChannelContext.getAlpha(0x11223344));
}
