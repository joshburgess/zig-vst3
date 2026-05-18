const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const istringresult = @import("pluginterfaces/base/istringresult.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");

pub fn StringResult(comptime max_text8_bytes: usize, comptime max_text16_units: usize) type {
    if (max_text8_bytes == 0) @compileError("StringResult requires at least one byte for text8");
    if (max_text16_units == 0) @compileError("StringResult requires at least one code unit for text16");

    return extern struct {
        const Self = @This();

        result_iface: istringresult.IStringResult = .{ .vtable = &result_vtable },
        string_iface: istringresult.IString = .{ .vtable = &string_vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        text8: [max_text8_bytes]types.char8 = [_]types.char8{0} ** max_text8_bytes,
        text16: [max_text16_units]types.char16 = [_]types.char16{0} ** max_text16_units,
        wide: bool = false,

        pub fn asResult(self: *Self) *istringresult.IStringResult {
            return &self.result_iface;
        }

        pub fn asString(self: *Self) *istringresult.IString {
            return &self.string_iface;
        }

        pub fn text8Span(self: *const Self) []const types.char8 {
            return std.mem.sliceTo(&self.text8, 0);
        }

        pub fn text16Span(self: *const Self) []const types.char16 {
            return std.mem.sliceTo(&self.text16, 0);
        }

        fn ownerFromResult(ptr: *anyopaque) *Self {
            const iface: *istringresult.IStringResult = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("result_iface", iface);
        }

        fn ownerFromString(ptr: *anyopaque) *Self {
            const iface: *istringresult.IString = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("string_iface", iface);
        }

        fn copyText8(self: *Self, value: ?[*:0]const types.char8) void {
            @memset(&self.text8, 0);
            @memset(&self.text16, 0);
            if (value) |text| {
                const len = @min(std.mem.len(text), max_text8_bytes - 1);
                @memcpy(self.text8[0..len], text[0..len]);
            }
            self.wide = false;
        }

        fn copyText16(self: *Self, value: ?[*:0]const types.char16) void {
            @memset(&self.text8, 0);
            @memset(&self.text16, 0);
            if (value) |text| {
                const len = @min(std.mem.len(text), max_text16_units - 1);
                @memcpy(self.text16[0..len], text[0..len]);
            }
            self.wide = true;
        }

        fn queryCanonical(self: *Self, add_ref_ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.result_iface },
                .{ .iid = &istringresult.istring_result_iid, .ptr = &self.result_iface },
                .{ .iid = &istringresult.istring_iid, .ptr = &self.string_iface },
            };
            return interface_map.queryWithAddRef(add_ref_ptr, resultAddRef, &entries, requested_iid, out);
        }

        fn resultQuery(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            return ownerFromResult(ptr).queryCanonical(ptr, requested_iid, out);
        }

        fn stringQuery(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const self = ownerFromString(ptr);
            return self.queryCanonical(&self.result_iface, requested_iid, out);
        }

        fn resultAddRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&ownerFromResult(ptr).ref_count, "FUnknown");
        }

        fn stringAddRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&ownerFromString(ptr).ref_count, "FUnknown");
        }

        fn resultRelease(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&ownerFromResult(ptr).ref_count, "IStringResult");
        }

        fn stringRelease(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&ownerFromString(ptr).ref_count, "IString");
        }

        fn resultSetText(ptr: *anyopaque, value: ?[*:0]const types.char8) callconv(.c) void {
            ownerFromResult(ptr).copyText8(value);
        }

        fn stringSetText8(ptr: *anyopaque, value: ?[*:0]const types.char8) callconv(.c) void {
            ownerFromString(ptr).copyText8(value);
        }

        fn stringSetText16(ptr: *anyopaque, value: ?[*:0]const types.char16) callconv(.c) void {
            ownerFromString(ptr).copyText16(value);
        }

        fn stringGetText8(ptr: *anyopaque) callconv(.c) ?[*:0]const types.char8 {
            return @ptrCast(&ownerFromString(ptr).text8);
        }

        fn stringGetText16(ptr: *anyopaque) callconv(.c) ?[*:0]const types.char16 {
            return @ptrCast(&ownerFromString(ptr).text16);
        }

        fn stringTake(_: *anyopaque, _: ?*anyopaque, _: bool) callconv(.c) void {}

        fn stringIsWideString(ptr: *anyopaque) callconv(.c) bool {
            return ownerFromString(ptr).wide;
        }

        const result_vtable = istringresult.IStringResultVTable{
            .queryInterface = resultQuery,
            .addRef = resultAddRef,
            .release = resultRelease,
            .setText = resultSetText,
        };

        const string_vtable = istringresult.IStringVTable{
            .queryInterface = stringQuery,
            .addRef = stringAddRef,
            .release = stringRelease,
            .setText8 = stringSetText8,
            .setText16 = stringSetText16,
            .getText8 = stringGetText8,
            .getText16 = stringGetText16,
            .take = stringTake,
            .isWideString = stringIsWideString,
        };
    };
}

test "string result stores text through legacy result interface" {
    const Result = StringResult(8, 8);
    var result = Result{};
    const iface = result.asResult();

    iface.vtable.setText(iface, "abcdefghi");

    try std.testing.expectEqualStrings("abcdefg", result.text8Span());
    try std.testing.expect(!result.asString().vtable.isWideString(result.asString()));
}

test "string result stores narrow and wide string values" {
    const Result = StringResult(16, 8);
    var result = Result{};
    const iface = result.asString();

    iface.vtable.setText8(iface, "gain");
    try std.testing.expectEqualStrings("gain", std.mem.span(iface.vtable.getText8(iface).?));
    try std.testing.expect(!iface.vtable.isWideString(iface));

    const wide_value = [_:0]types.char16{ 'O', 'K' };
    iface.vtable.setText16(iface, &wide_value);
    try std.testing.expectEqualSlices(types.char16, &.{ 'O', 'K' }, result.text16Span());
    try std.testing.expect(iface.vtable.isWideString(iface));
}

test "string result clears null narrow and wide inputs" {
    const Result = StringResult(8, 8);
    var result = Result{};
    const iface = result.asString();

    iface.vtable.setText8(iface, "gain");
    iface.vtable.setText8(iface, null);
    try std.testing.expectEqualStrings("", result.text8Span());
    try std.testing.expect(!iface.vtable.isWideString(iface));

    const wide_value = [_:0]types.char16{ 'O', 'K' };
    iface.vtable.setText16(iface, &wide_value);
    iface.vtable.setText16(iface, null);
    try std.testing.expectEqualSlices(types.char16, &.{}, result.text16Span());
    try std.testing.expect(iface.vtable.isWideString(iface));
}

test "string result clears inactive encoding when switching text width" {
    const Result = StringResult(8, 8);
    var result = Result{};
    const iface = result.asString();

    iface.vtable.setText8(iface, "gain");
    try std.testing.expectEqualStrings("gain", result.text8Span());

    const wide_value = [_:0]types.char16{ 'O', 'K' };
    iface.vtable.setText16(iface, &wide_value);
    try std.testing.expectEqualStrings("", result.text8Span());
    try std.testing.expectEqualSlices(types.char16, &.{ 'O', 'K' }, result.text16Span());
    try std.testing.expect(iface.vtable.isWideString(iface));

    iface.vtable.setText8(iface, "mix");
    try std.testing.expectEqualStrings("mix", result.text8Span());
    try std.testing.expectEqualSlices(types.char16, &.{}, result.text16Span());
    try std.testing.expect(!iface.vtable.isWideString(iface));
}

test "string result truncates narrow and wide text with trailing zero" {
    const Result = StringResult(4, 3);
    var result = Result{};
    const iface = result.asString();

    iface.vtable.setText8(iface, "abcdef");
    try std.testing.expectEqualStrings("abc", result.text8Span());
    try std.testing.expectEqual(@as(types.char8, 0), result.text8[3]);

    const wide_value = [_:0]types.char16{ 'A', 'B', 'C', 'D' };
    iface.vtable.setText16(iface, &wide_value);
    try std.testing.expectEqualSlices(types.char16, &.{ 'A', 'B' }, result.text16Span());
    try std.testing.expectEqual(@as(types.char16, 0), result.text16[2]);
}

test "string result supports both string interfaces" {
    const Result = StringResult(8, 8);
    var result = Result{};
    const iface = result.asResult();

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &istringresult.istring_iid, &queried));
    try std.testing.expect(queried != null);
    const string_iface: *istringresult.IString = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), string_iface.vtable.release(string_iface));
}

test "string result query works from string side and clears unsupported outputs" {
    const Result = StringResult(8, 8);
    var result = Result{};
    const iface = result.asString();

    var queried_result: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &istringresult.istring_result_iid, &queried_result));
    try std.testing.expect(queried_result != null);
    const result_iface: *istringresult.IStringResult = @ptrCast(@alignCast(queried_result.?));
    try std.testing.expectEqual(@as(types.uint32, 1), result_iface.vtable.release(result_iface));

    var missing: ?*anyopaque = @ptrCast(iface);
    try std.testing.expectEqual(types.kNoInterface, iface.vtable.queryInterface(iface, &tuid.zero, &missing));
    try std.testing.expectEqual(@as(?*anyopaque, null), missing);
}
