const base_types = @import("types.zig");

pub const FVariant = extern struct {
    type: base_types.uint16 = 0,
    value: extern union {
        intValue: base_types.int64,
        floatValue: f64,
        string8: ?[*:0]const base_types.char8,
        string16: ?[*:0]const base_types.char16,
        object: ?*anyopaque,
    } = .{ .intValue = 0 },

    pub const kEmpty: base_types.uint16 = 0;
    pub const kInteger: base_types.uint16 = 1 << 0;
    pub const kFloat: base_types.uint16 = 1 << 1;
    pub const kString8: base_types.uint16 = 1 << 2;
    pub const kObject: base_types.uint16 = 1 << 3;
    pub const kOwner: base_types.uint16 = 1 << 4;
    pub const kString16: base_types.uint16 = 1 << 5;
};

pub const kEmpty = FVariant.kEmpty;
pub const kInteger = FVariant.kInteger;
pub const kFloat = FVariant.kFloat;
pub const kString8 = FVariant.kString8;
pub const kObject = FVariant.kObject;
pub const kOwner = FVariant.kOwner;
pub const kString16 = FVariant.kString16;

test "variant layout matches SDK layout" {
    try @import("std").testing.expectEqual(@as(usize, 16), @sizeOf(FVariant));
    try @import("std").testing.expectEqual(@as(usize, 8), @alignOf(FVariant));
}
