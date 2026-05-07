const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const itest = @import("pluginterfaces/test/itest.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");

pub fn TestResult(comptime max_messages: usize, comptime max_chars: usize) type {
    if (max_messages == 0) @compileError("TestResult requires at least one message slot");
    if (max_chars == 0) @compileError("TestResult requires at least one char per message");

    return extern struct {
        const Self = @This();

        iface: itest.ITestResult = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        error_count: types.uint32 = 0,
        message_count: types.uint32 = 0,
        errors: [max_messages][max_chars]types.char16 = [_][max_chars]types.char16{[_]types.char16{0} ** max_chars} ** max_messages,
        messages: [max_messages][max_chars]types.char16 = [_][max_chars]types.char16{[_]types.char16{0} ** max_chars} ** max_messages,

        pub fn asInterface(self: *Self) *itest.ITestResult {
            return &self.iface;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *itest.ITestResult = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &itest.itest_result_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.C) types.uint32 {
            return owner(ptr).ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn release(ptr: *anyopaque) callconv(.C) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "ITestResult");
        }

        fn addErrorMessage(ptr: *anyopaque, text: ?[*:0]const types.char16) callconv(.C) void {
            owner(ptr).store(&owner(ptr).errors, &owner(ptr).error_count, text);
        }

        fn addMessage(ptr: *anyopaque, text: ?[*:0]const types.char16) callconv(.C) void {
            owner(ptr).store(&owner(ptr).messages, &owner(ptr).message_count, text);
        }

        fn store(self: *Self, target: *[max_messages][max_chars]types.char16, count: *types.uint32, text: ?[*:0]const types.char16) void {
            const index = count.*;
            if (index < max_messages) {
                @memset(&target[index], 0);
                if (text) |value| {
                    const span = std.mem.span(value);
                    const len = @min(span.len, max_chars - 1);
                    @memcpy(target[index][0..len], span[0..len]);
                }
            }
            _ = self;
            count.* += 1;
        }

        pub fn errorMessage(self: *const Self, index: usize) []const types.char16 {
            return std.mem.sliceTo(&self.errors[index], 0);
        }

        pub fn message(self: *const Self, index: usize) []const types.char16 {
            return std.mem.sliceTo(&self.messages[index], 0);
        }

        const vtable = itest.ITestResultVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .addErrorMessage = addErrorMessage,
            .addMessage = addMessage,
        };
    };
}

pub fn Test(comptime Config: type) type {
    return extern struct {
        const Self = @This();

        iface: itest.ITest = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        setup_count: types.uint32 = 0,
        run_count: types.uint32 = 0,
        teardown_count: types.uint32 = 0,
        last_result: ?*itest.ITestResult = null,

        pub fn asInterface(self: *Self) *itest.ITest {
            return &self.iface;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *itest.ITest = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &itest.itest_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.C) types.uint32 {
            return owner(ptr).ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn release(ptr: *anyopaque) callconv(.C) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "ITest");
        }

        fn setup(ptr: *anyopaque) callconv(.C) bool {
            const self = owner(ptr);
            self.setup_count += 1;
            if (@hasDecl(Config, "setup")) return Config.setup(self);
            return true;
        }

        fn run(ptr: *anyopaque, result: ?*itest.ITestResult) callconv(.C) bool {
            const self = owner(ptr);
            self.run_count += 1;
            self.last_result = result;
            if (@hasDecl(Config, "run")) return Config.run(self, result);
            return true;
        }

        fn teardown(ptr: *anyopaque) callconv(.C) bool {
            const self = owner(ptr);
            self.teardown_count += 1;
            if (@hasDecl(Config, "teardown")) return Config.teardown(self);
            return true;
        }

        fn getDescription(_: *anyopaque) callconv(.C) ?[*:0]const types.char16 {
            if (@hasDecl(Config, "description")) return Config.description;
            return null;
        }

        const vtable = itest.ITestVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .setup = setup,
            .run = run,
            .teardown = teardown,
            .getDescription = getDescription,
        };
    };
}

test "test result stores messages and errors" {
    const Result = TestResult(2, 8);
    var result = Result{};
    const iface = result.asInterface();
    const error_text = std.unicode.utf8ToUtf16LeStringLiteral("failed");
    const message_text = std.unicode.utf8ToUtf16LeStringLiteral("ok");

    iface.vtable.addErrorMessage(iface, error_text);
    iface.vtable.addMessage(iface, message_text);

    try std.testing.expectEqual(@as(types.uint32, 1), result.error_count);
    try std.testing.expectEqual(@as(types.uint32, 1), result.message_count);
    try std.testing.expectEqualSlices(types.char16, error_text[0..6], result.errorMessage(0));
    try std.testing.expectEqualSlices(types.char16, message_text[0..2], result.message(0));
}

test "test result counts messages past fixed storage" {
    const Result = TestResult(1, 4);
    var result = Result{};
    const iface = result.asInterface();
    const text = std.unicode.utf8ToUtf16LeStringLiteral("abcd");

    iface.vtable.addMessage(iface, text);
    iface.vtable.addMessage(iface, text);

    try std.testing.expectEqual(@as(types.uint32, 2), result.message_count);
    try std.testing.expectEqualSlices(types.char16, text[0..3], result.message(0));
}

test "test object tracks default lifecycle calls" {
    const TestObject = Test(struct {});
    const Result = TestResult(1, 1);
    var object = TestObject{};
    var result = Result{};
    const iface = object.asInterface();

    try std.testing.expect(iface.vtable.setup(iface));
    try std.testing.expect(iface.vtable.run(iface, result.asInterface()));
    try std.testing.expect(iface.vtable.teardown(iface));
    try std.testing.expectEqual(@as(types.uint32, 1), object.setup_count);
    try std.testing.expectEqual(@as(types.uint32, 1), object.run_count);
    try std.testing.expectEqual(@as(types.uint32, 1), object.teardown_count);
    try std.testing.expectEqual(result.asInterface(), object.last_result.?);
}

test "test object delegates lifecycle hooks and description" {
    const expected_description = std.unicode.utf8ToUtf16LeStringLiteral("custom");
    const TestObject = Test(struct {
        pub const description = expected_description;

        pub fn setup(self: anytype) bool {
            _ = self;
            return false;
        }

        pub fn run(self: anytype, result: ?*itest.ITestResult) bool {
            _ = self;
            return result != null;
        }

        pub fn teardown(self: anytype) bool {
            _ = self;
            return false;
        }
    });
    const Result = TestResult(1, 1);
    var object = TestObject{};
    var result = Result{};
    const iface = object.asInterface();

    try std.testing.expect(!iface.vtable.setup(iface));
    try std.testing.expect(!iface.vtable.run(iface, null));
    try std.testing.expect(iface.vtable.run(iface, result.asInterface()));
    try std.testing.expect(!iface.vtable.teardown(iface));
    try std.testing.expectEqual(expected_description, iface.vtable.getDescription(iface).?);
}

test "test interfaces support query interface" {
    const TestObject = Test(struct {});
    const Result = TestResult(1, 1);
    var object = TestObject{};
    var result = Result{};

    var queried_test: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, object.asInterface().vtable.queryInterface(object.asInterface(), &itest.itest_iid, &queried_test));
    try std.testing.expect(queried_test != null);
    const queried_test_iface: *itest.ITest = @ptrCast(@alignCast(queried_test.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_test_iface.vtable.release(queried_test_iface));

    var queried_result: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, result.asInterface().vtable.queryInterface(result.asInterface(), &itest.itest_result_iid, &queried_result));
    try std.testing.expect(queried_result != null);
    const queried_result_iface: *itest.ITestResult = @ptrCast(@alignCast(queried_result.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_result_iface.vtable.release(queried_result_iface));
}
