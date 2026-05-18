const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const ierrorcontext = @import("pluginterfaces/base/ierrorcontext.zig");
const istringresult = @import("pluginterfaces/base/istringresult.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const vst_string_result = @import("vst_string_result.zig");

pub fn ErrorContext(comptime max_message_bytes: usize) type {
    if (max_message_bytes == 0) @compileError("ErrorContext requires at least one byte for the message");

    return extern struct {
        const Self = @This();

        iface: ierrorcontext.IErrorContext = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        message: [max_message_bytes]types.char8 = [_]types.char8{0} ** max_message_bytes,
        error_ui_disabled: bool = false,
        shown: bool = false,

        pub fn asInterface(self: *Self) *ierrorcontext.IErrorContext {
            return &self.iface;
        }

        pub fn setMessage(self: *Self, value: []const u8) void {
            @memset(&self.message, 0);
            const len = @min(value.len, max_message_bytes - 1);
            @memcpy(self.message[0..len], value[0..len]);
        }

        pub fn messageSpan(self: *const Self) []const u8 {
            return std.mem.sliceTo(&self.message, 0);
        }

        pub fn isErrorUiDisabled(self: *const Self) bool {
            return self.error_ui_disabled;
        }

        pub fn wasShown(self: *const Self) bool {
            return self.shown;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *ierrorcontext.IErrorContext = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ierrorcontext.ierror_context_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IErrorContext");
        }

        fn disableErrorUI(ptr: *anyopaque, state: bool) callconv(.c) void {
            owner(ptr).error_ui_disabled = state;
        }

        fn errorMessageShown(ptr: *anyopaque) callconv(.c) types.tresult {
            owner(ptr).shown = true;
            return types.kResultOk;
        }

        fn getErrorMessage(ptr: *anyopaque, out: ?*istringresult.IString) callconv(.c) types.tresult {
            const target = out orelse return types.kInvalidArgument;
            target.vtable.setText8(target, @ptrCast(&owner(ptr).message));
            return types.kResultOk;
        }

        const vtable = ierrorcontext.IErrorContextVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .disableErrorUI = disableErrorUI,
            .errorMessageShown = errorMessageShown,
            .getErrorMessage = getErrorMessage,
        };
    };
}

test "error context stores flags and writes message" {
    const Context = ErrorContext(16);
    const String = vst_string_result.StringResult(32, 8);
    var context = Context{};
    var string = String{};
    const iface = context.asInterface();

    context.setMessage("plugin failed");
    iface.vtable.disableErrorUI(iface, true);

    try std.testing.expect(context.isErrorUiDisabled());
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getErrorMessage(iface, string.asString()));
    try std.testing.expectEqualStrings("plugin failed", string.text8Span());
    try std.testing.expectEqual(types.kResultOk, iface.vtable.errorMessageShown(iface));
    try std.testing.expect(context.wasShown());
}

test "error context truncates messages to fixed capacity" {
    const Context = ErrorContext(5);
    var context = Context{};

    context.setMessage("abcdef");

    try std.testing.expectEqualStrings("abcd", context.messageSpan());
}

test "error context rejects missing output string" {
    const Context = ErrorContext(8);
    var context = Context{};
    const iface = context.asInterface();

    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.getErrorMessage(iface, null));
}

test "error context supports query interface" {
    const Context = ErrorContext(8);
    var context = Context{};
    const iface = context.asInterface();

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &ierrorcontext.ierror_context_iid, &queried));
    try std.testing.expect(queried != null);
    const queried_context: *ierrorcontext.IErrorContext = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_context.vtable.release(queried_context));
}

test "error context clears unsupported query output" {
    const Context = ErrorContext(8);
    var context = Context{};
    const iface = context.asInterface();

    var queried: ?*anyopaque = @ptrFromInt(0x1000);
    try std.testing.expectEqual(types.kNoInterface, iface.vtable.queryInterface(iface, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
}
