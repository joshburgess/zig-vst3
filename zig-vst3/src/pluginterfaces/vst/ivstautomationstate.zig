const base_types = @import("../base/types.zig");
const tuid = @import("../../tuid.zig");

pub const iautomation_state_iid = tuid.inlineUid(0xB4E8287F, 0x1BB346AA, 0x83A46667, 0x68937BAB);

pub const AutomationStates = packed struct(base_types.int32) {
    read_state: bool = false,
    write_state: bool = false,
    _: u30 = 0,

    pub const kNoAutomation: base_types.int32 = 0;
    pub const kReadState: base_types.int32 = 1 << 0;
    pub const kWriteState: base_types.int32 = 1 << 1;
    pub const kReadWriteState: base_types.int32 = kReadState | kWriteState;
};

pub const IAutomationStateVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    setAutomationState: *const fn (*anyopaque, base_types.int32) callconv(.c) base_types.tresult,
};

pub const IAutomationState = extern struct {
    vtable: *const IAutomationStateVTable,
};

test "automation state vtable slot count includes FUnknown prefix" {
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IAutomationState));
    try @import("std").testing.expectEqual(@as(usize, 4), @typeInfo(IAutomationStateVTable).@"struct".fields.len);
}
