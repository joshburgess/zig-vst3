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

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &itest.itest_result_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "ITestResult");
        }

        fn addErrorMessage(ptr: *anyopaque, text: ?[*:0]const types.char16) callconv(.c) void {
            owner(ptr).store(&owner(ptr).errors, &owner(ptr).error_count, text);
        }

        fn addMessage(ptr: *anyopaque, text: ?[*:0]const types.char16) callconv(.c) void {
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

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &itest.itest_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "ITest");
        }

        fn setup(ptr: *anyopaque) callconv(.c) bool {
            const self = owner(ptr);
            self.setup_count += 1;
            if (@hasDecl(Config, "setup")) return Config.setup(self);
            return true;
        }

        fn run(ptr: *anyopaque, result: ?*itest.ITestResult) callconv(.c) bool {
            const self = owner(ptr);
            self.run_count += 1;
            self.last_result = result;
            if (@hasDecl(Config, "run")) return Config.run(self, result);
            return true;
        }

        fn teardown(ptr: *anyopaque) callconv(.c) bool {
            const self = owner(ptr);
            self.teardown_count += 1;
            if (@hasDecl(Config, "teardown")) return Config.teardown(self);
            return true;
        }

        fn getDescription(_: *anyopaque) callconv(.c) ?[*:0]const types.char16 {
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

pub fn TestSuite(comptime max_tests: usize, comptime max_suites: usize) type {
    if (max_tests == 0) @compileError("TestSuite requires at least one test slot");
    if (max_suites == 0) @compileError("TestSuite requires at least one nested suite slot");

    return extern struct {
        const Self = @This();

        const TestEntry = extern struct {
            name: ?types.FIDString = null,
            test_iface: ?*itest.ITest = null,
        };

        const SuiteEntry = extern struct {
            name: ?types.FIDString = null,
            suite: ?*itest.ITestSuite = null,
        };

        iface: itest.ITestSuite = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        test_count: types.uint32 = 0,
        suite_count: types.uint32 = 0,
        tests: [max_tests]TestEntry = [_]TestEntry{.{}} ** max_tests,
        suites: [max_suites]SuiteEntry = [_]SuiteEntry{.{}} ** max_suites,
        environment: ?*itest.ITest = null,

        pub fn asInterface(self: *Self) *itest.ITestSuite {
            return &self.iface;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *itest.ITestSuite = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &itest.itest_suite_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "ITestSuite");
        }

        fn addTest(ptr: *anyopaque, name: types.FIDString, test_iface: ?*itest.ITest) callconv(.c) types.tresult {
            const self = owner(ptr);
            const index = self.test_count;
            self.test_count += 1;
            if (index >= max_tests) return types.kResultFalse;
            if (test_iface) |value| _ = value.vtable.addRef(value);
            self.tests[index] = .{ .name = name, .test_iface = test_iface };
            return types.kResultOk;
        }

        fn addTestSuite(ptr: *anyopaque, name: types.FIDString, suite_iface: ?*itest.ITestSuite) callconv(.c) types.tresult {
            const self = owner(ptr);
            const index = self.suite_count;
            self.suite_count += 1;
            if (index >= max_suites) return types.kResultFalse;
            if (suite_iface) |value| _ = value.vtable.addRef(value);
            self.suites[index] = .{ .name = name, .suite = suite_iface };
            return types.kResultOk;
        }

        fn setEnvironment(ptr: *anyopaque, environment: ?*itest.ITest) callconv(.c) types.tresult {
            const self = owner(ptr);
            if (environment) |value| _ = value.vtable.addRef(value);
            if (self.environment) |previous| _ = previous.vtable.release(previous);
            self.environment = environment;
            return types.kResultOk;
        }

        const vtable = itest.ITestSuiteVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .addTest = addTest,
            .addTestSuite = addTestSuite,
            .setEnvironment = setEnvironment,
        };
    };
}

pub fn TestFactory(comptime Config: type) type {
    return extern struct {
        const Self = @This();

        iface: itest.ITestFactory = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        create_count: types.uint32 = 0,
        last_context: ?*anyopaque = null,
        last_suite: ?*itest.ITestSuite = null,

        pub fn asInterface(self: *Self) *itest.ITestFactory {
            return &self.iface;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *itest.ITestFactory = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &itest.itest_factory_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "ITestFactory");
        }

        fn createTests(ptr: *anyopaque, context: ?*anyopaque, suite: ?*itest.ITestSuite) callconv(.c) types.tresult {
            const self = owner(ptr);
            self.create_count += 1;
            self.last_context = context;
            self.last_suite = suite;
            if (@hasDecl(Config, "createTests")) return Config.createTests(self, context, suite);
            return types.kResultOk;
        }

        const vtable = itest.ITestFactoryVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .createTests = createTests,
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

test "test result records null messages as empty entries" {
    const Result = TestResult(1, 4);
    var result = Result{};
    const iface = result.asInterface();

    iface.vtable.addErrorMessage(iface, null);
    iface.vtable.addMessage(iface, null);

    try std.testing.expectEqual(@as(types.uint32, 1), result.error_count);
    try std.testing.expectEqual(@as(types.uint32, 1), result.message_count);
    try std.testing.expectEqualSlices(types.char16, &[_]types.char16{}, result.errorMessage(0));
    try std.testing.expectEqualSlices(types.char16, &[_]types.char16{}, result.message(0));
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

test "test suite stores tests suites and environment" {
    const Suite = TestSuite(1, 1);
    const TestObject = Test(struct {});
    var suite = Suite{};
    var nested = Suite{};
    var test_object = TestObject{};
    const iface = suite.asInterface();
    const test_iface = test_object.asInterface();
    const nested_iface = nested.asInterface();

    try std.testing.expectEqual(types.kResultOk, iface.vtable.addTest(iface, "case", test_iface));
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.addTest(iface, "overflow", null));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.addTestSuite(iface, "nested", nested_iface));
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.addTestSuite(iface, "overflow", null));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.setEnvironment(iface, test_iface));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.setEnvironment(iface, null));

    try std.testing.expectEqual(@as(types.uint32, 2), suite.test_count);
    try std.testing.expectEqual(@as(types.uint32, 2), suite.suite_count);
    try std.testing.expectEqualStrings("case", std.mem.span(suite.tests[0].name.?));
    try std.testing.expectEqual(test_iface, suite.tests[0].test_iface.?);
    try std.testing.expectEqualStrings("nested", std.mem.span(suite.suites[0].name.?));
    try std.testing.expectEqual(nested_iface, suite.suites[0].suite.?);
    try std.testing.expectEqual(@as(?*itest.ITest, null), suite.environment);
}

test "test suite rejects overflow without retaining rejected entries" {
    const Suite = TestSuite(1, 1);
    const TestObject = Test(struct {});
    var suite = Suite{};
    var nested = Suite{};
    var first = TestObject{};
    var rejected = TestObject{};
    const iface = suite.asInterface();

    try std.testing.expectEqual(types.kResultOk, iface.vtable.addTest(iface, "first", first.asInterface()));
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.addTest(iface, "rejected", rejected.asInterface()));
    try std.testing.expectEqual(@as(types.uint32, 2), first.ref_count.load(.monotonic));
    try std.testing.expectEqual(@as(types.uint32, 1), rejected.ref_count.load(.monotonic));
    try std.testing.expectEqual(first.asInterface(), suite.tests[0].test_iface.?);

    try std.testing.expectEqual(types.kResultOk, iface.vtable.addTestSuite(iface, "nested", nested.asInterface()));
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.addTestSuite(iface, "rejected", nested.asInterface()));
    try std.testing.expectEqual(@as(types.uint32, 2), nested.ref_count.load(.monotonic));
    try std.testing.expectEqual(nested.asInterface(), suite.suites[0].suite.?);
}

test "test suite retains and releases replacement environments" {
    const Suite = TestSuite(1, 1);
    const TestObject = Test(struct {});
    var suite = Suite{};
    var first = TestObject{};
    var second = TestObject{};
    const iface = suite.asInterface();

    try std.testing.expectEqual(types.kResultOk, iface.vtable.setEnvironment(iface, first.asInterface()));
    try std.testing.expectEqual(@as(types.uint32, 2), first.ref_count.load(.monotonic));
    try std.testing.expectEqual(first.asInterface(), suite.environment.?);

    try std.testing.expectEqual(types.kResultOk, iface.vtable.setEnvironment(iface, second.asInterface()));
    try std.testing.expectEqual(@as(types.uint32, 1), first.ref_count.load(.monotonic));
    try std.testing.expectEqual(@as(types.uint32, 2), second.ref_count.load(.monotonic));
    try std.testing.expectEqual(second.asInterface(), suite.environment.?);

    try std.testing.expectEqual(types.kResultOk, iface.vtable.setEnvironment(iface, null));
    try std.testing.expectEqual(@as(types.uint32, 1), second.ref_count.load(.monotonic));
    try std.testing.expectEqual(@as(?*itest.ITest, null), suite.environment);
}

test "test factory tracks create calls and delegates hook" {
    const Factory = TestFactory(struct {
        pub fn createTests(self: anytype, context: ?*anyopaque, suite: ?*itest.ITestSuite) types.tresult {
            _ = self;
            return if (context != null and suite != null) types.kResultOk else types.kInvalidArgument;
        }
    });
    const Suite = TestSuite(1, 1);
    var factory = Factory{};
    var suite = Suite{};
    const iface = factory.asInterface();
    const context: *anyopaque = @ptrFromInt(0x1000);

    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.createTests(iface, null, null));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.createTests(iface, context, suite.asInterface()));
    try std.testing.expectEqual(@as(types.uint32, 2), factory.create_count);
    try std.testing.expectEqual(context, factory.last_context.?);
    try std.testing.expectEqual(suite.asInterface(), factory.last_suite.?);
}

test "test interfaces support query interface" {
    const TestObject = Test(struct {});
    const Result = TestResult(1, 1);
    const Suite = TestSuite(1, 1);
    const Factory = TestFactory(struct {});
    var object = TestObject{};
    var result = Result{};
    var suite = Suite{};
    var factory = Factory{};

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

    var queried_suite: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, suite.asInterface().vtable.queryInterface(suite.asInterface(), &itest.itest_suite_iid, &queried_suite));
    try std.testing.expect(queried_suite != null);
    const queried_suite_iface: *itest.ITestSuite = @ptrCast(@alignCast(queried_suite.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_suite_iface.vtable.release(queried_suite_iface));

    var queried_factory: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, factory.asInterface().vtable.queryInterface(factory.asInterface(), &itest.itest_factory_iid, &queried_factory));
    try std.testing.expect(queried_factory != null);
    const queried_factory_iface: *itest.ITestFactory = @ptrCast(@alignCast(queried_factory.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_factory_iface.vtable.release(queried_factory_iface));
}
