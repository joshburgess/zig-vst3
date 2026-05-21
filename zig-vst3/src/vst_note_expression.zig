const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const ivstnoteexpression = @import("pluginterfaces/vst/ivstnoteexpression.zig");
const string128 = @import("string128.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const vst_index = @import("vst_index.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");

pub fn NoteExpressionController(comptime max_expressions: usize, comptime max_keyswitches: usize, comptime Config: type) type {
    if (max_expressions == 0 and max_keyswitches == 0) @compileError("NoteExpressionController requires at least one expression or keyswitch slot");
    vst_index.requireInt32Capacity(max_expressions, "NoteExpressionController expression capacity");
    vst_index.requireInt32Capacity(max_keyswitches, "NoteExpressionController keyswitch capacity");

    return extern struct {
        const Self = @This();

        note_expression: ivstnoteexpression.INoteExpressionController = .{ .vtable = &note_expression_vtable },
        keyswitch: ivstnoteexpression.IKeyswitchController = .{ .vtable = &keyswitch_vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        expression_count: types.uint32 = 0,
        keyswitch_count: types.uint32 = 0,
        expressions: [max_expressions]ivstnoteexpression.NoteExpressionTypeInfo = [_]ivstnoteexpression.NoteExpressionTypeInfo{.{}} ** max_expressions,
        keyswitches: [max_keyswitches]ivstnoteexpression.KeyswitchInfo = [_]ivstnoteexpression.KeyswitchInfo{.{}} ** max_keyswitches,
        last_bus: types.int32 = 0,
        last_channel: types.int16 = 0,

        fn safeExpressionCount(self: *const Self) usize {
            return vst_index.clampedCountU32(self.expression_count, max_expressions);
        }

        fn safeKeyswitchCount(self: *const Self) usize {
            return vst_index.clampedCountU32(self.keyswitch_count, max_keyswitches);
        }

        pub fn asNoteExpression(self: *Self) *ivstnoteexpression.INoteExpressionController {
            return &self.note_expression;
        }

        pub fn asKeyswitch(self: *Self) *ivstnoteexpression.IKeyswitchController {
            return &self.keyswitch;
        }

        fn recordBusContext(self: *Self, bus_index: types.int32, channel: types.int16) void {
            self.last_bus = bus_index;
            self.last_channel = channel;
        }

        fn appendExpressionIndex(self: *Self, info: ivstnoteexpression.NoteExpressionTypeInfo) ?usize {
            const index = vst_index.appendIndexU32(self.expression_count, max_expressions) orelse return null;
            self.expressions[index] = info;
            self.expression_count +|= 1;
            return index;
        }

        pub fn addExpression(self: *Self, info: ivstnoteexpression.NoteExpressionTypeInfo) types.tresult {
            _ = self.appendExpressionIndex(info) orelse return types.kResultFalse;
            return types.kResultOk;
        }

        fn appendKeyswitchIndex(self: *Self, info: ivstnoteexpression.KeyswitchInfo) ?usize {
            const index = vst_index.appendIndexU32(self.keyswitch_count, max_keyswitches) orelse return null;
            self.keyswitches[index] = info;
            self.keyswitch_count +|= 1;
            return index;
        }

        pub fn addKeyswitch(self: *Self, info: ivstnoteexpression.KeyswitchInfo) types.tresult {
            _ = self.appendKeyswitchIndex(info) orelse return types.kResultFalse;
            return types.kResultOk;
        }

        pub fn expressionByIndex(self: *const Self, index: types.int32) ?ivstnoteexpression.NoteExpressionTypeInfo {
            const expression_index = vst_index.bounded(index, self.safeExpressionCount()) orelse return null;
            return self.expressions[expression_index];
        }

        pub fn keyswitchByIndex(self: *const Self, index: types.int32) ?ivstnoteexpression.KeyswitchInfo {
            const keyswitch_index = vst_index.bounded(index, self.safeKeyswitchCount()) orelse return null;
            return self.keyswitches[keyswitch_index];
        }

        const ownerFromNoteExpression = interface_map.ownerFromField(Self, ivstnoteexpression.INoteExpressionController, "note_expression");
        const ownerFromKeyswitch = interface_map.ownerFromField(Self, ivstnoteexpression.IKeyswitchController, "keyswitch");

        fn queryCanonical(self: *Self, add_ref_ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.note_expression },
                .{ .iid = &ivstnoteexpression.inote_expression_controller_iid, .ptr = &self.note_expression },
                .{ .iid = &ivstnoteexpression.ikeyswitch_controller_iid, .ptr = &self.keyswitch },
            };
            return interface_map.queryWithAddRef(add_ref_ptr, noteExpressionAddRef, &entries, requested_iid, out);
        }

        fn noteExpressionQuery(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            return ownerFromNoteExpression(ptr).queryCanonical(ptr, requested_iid, out);
        }

        fn keyswitchQuery(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const self = ownerFromKeyswitch(ptr);
            return self.queryCanonical(&self.note_expression, requested_iid, out);
        }

        fn noteExpressionAddRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&ownerFromNoteExpression(ptr).ref_count, "FUnknown");
        }

        fn keyswitchAddRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&ownerFromKeyswitch(ptr).ref_count, "FUnknown");
        }

        fn noteExpressionRelease(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&ownerFromNoteExpression(ptr).ref_count, "INoteExpressionController");
        }

        fn keyswitchRelease(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&ownerFromKeyswitch(ptr).ref_count, "IKeyswitchController");
        }

        fn getNoteExpressionCount(ptr: *anyopaque, bus_index: types.int32, channel: types.int16) callconv(.c) types.int32 {
            const self = ownerFromNoteExpression(ptr);
            self.recordBusContext(bus_index, channel);
            return vst_index.int32Count(self.safeExpressionCount());
        }

        fn failInfo(out: anytype) types.tresult {
            out.* = .{};
            return types.kInvalidArgument;
        }

        fn getNoteExpressionInfo(ptr: *anyopaque, bus_index: types.int32, channel: types.int16, index: types.int32, out: *ivstnoteexpression.NoteExpressionTypeInfo) callconv(.c) types.tresult {
            const self = ownerFromNoteExpression(ptr);
            self.recordBusContext(bus_index, channel);
            out.* = self.expressionByIndex(index) orelse return failInfo(out);
            return types.kResultOk;
        }

        fn failNoteExpressionString(out: [*]vsttypes.TChar, result: types.tresult) types.tresult {
            string128.clearPtr(out);
            return result;
        }

        fn getNoteExpressionStringByValue(ptr: *anyopaque, bus_index: types.int32, channel: types.int16, type_id: ivstnoteexpression.NoteExpressionTypeID, value: ivstnoteexpression.NoteExpressionValue, out: [*]vsttypes.TChar) callconv(.c) types.tresult {
            const self = ownerFromNoteExpression(ptr);
            self.recordBusContext(bus_index, channel);
            string128.clearPtr(out);
            if (@hasDecl(Config, "getNoteExpressionStringByValue")) {
                const result = Config.getNoteExpressionStringByValue(self, bus_index, channel, type_id, value, out);
                if (result != types.kResultOk) return failNoteExpressionString(out, result);
                return result;
            }
            return types.kResultFalse;
        }

        fn failNoteExpressionValue(out: *ivstnoteexpression.NoteExpressionValue, result: types.tresult) types.tresult {
            out.* = 0;
            return result;
        }

        fn getNoteExpressionValueByString(ptr: *anyopaque, bus_index: types.int32, channel: types.int16, type_id: ivstnoteexpression.NoteExpressionTypeID, text: [*:0]const vsttypes.TChar, out: *ivstnoteexpression.NoteExpressionValue) callconv(.c) types.tresult {
            const self = ownerFromNoteExpression(ptr);
            self.recordBusContext(bus_index, channel);
            out.* = 0;
            if (@hasDecl(Config, "getNoteExpressionValueByString")) {
                const result = Config.getNoteExpressionValueByString(self, bus_index, channel, type_id, text, out);
                if (result != types.kResultOk) return failNoteExpressionValue(out, result);
                return result;
            }
            return types.kResultFalse;
        }

        fn getKeyswitchCount(ptr: *anyopaque, bus_index: types.int32, channel: types.int16) callconv(.c) types.int32 {
            const self = ownerFromKeyswitch(ptr);
            self.recordBusContext(bus_index, channel);
            return vst_index.int32Count(self.safeKeyswitchCount());
        }

        fn getKeyswitchInfo(ptr: *anyopaque, bus_index: types.int32, channel: types.int16, index: types.int32, out: *ivstnoteexpression.KeyswitchInfo) callconv(.c) types.tresult {
            const self = ownerFromKeyswitch(ptr);
            self.recordBusContext(bus_index, channel);
            out.* = self.keyswitchByIndex(index) orelse return failInfo(out);
            return types.kResultOk;
        }

        const note_expression_vtable = ivstnoteexpression.INoteExpressionControllerVTable{
            .queryInterface = noteExpressionQuery,
            .addRef = noteExpressionAddRef,
            .release = noteExpressionRelease,
            .getNoteExpressionCount = getNoteExpressionCount,
            .getNoteExpressionInfo = getNoteExpressionInfo,
            .getNoteExpressionStringByValue = getNoteExpressionStringByValue,
            .getNoteExpressionValueByString = getNoteExpressionValueByString,
        };

        const keyswitch_vtable = ivstnoteexpression.IKeyswitchControllerVTable{
            .queryInterface = keyswitchQuery,
            .addRef = keyswitchAddRef,
            .release = keyswitchRelease,
            .getKeyswitchCount = getKeyswitchCount,
            .getKeyswitchInfo = getKeyswitchInfo,
        };
    };
}

test "note expression helper stores expression and keyswitch info" {
    const Helper = NoteExpressionController(1, 1, struct {});
    var helper = Helper{};
    const expression = helper.asNoteExpression();
    const keyswitch = helper.asKeyswitch();

    try std.testing.expectEqual(types.kResultOk, helper.addExpression(.{
        .typeId = @intFromEnum(ivstnoteexpression.NoteExpressionTypeIDs.kBrightnessTypeID),
        .valueDesc = .{ .defaultValue = 0.5, .minimum = 0, .maximum = 1, .stepCount = 0 },
        .associatedParameterId = 42,
    }));
    try std.testing.expectEqual(types.kResultFalse, helper.addExpression(.{ .typeId = @intFromEnum(ivstnoteexpression.NoteExpressionTypeIDs.kVibratoTypeID) }));
    try std.testing.expectEqual(@intFromEnum(ivstnoteexpression.NoteExpressionTypeIDs.kBrightnessTypeID), helper.expressionByIndex(0).?.typeId);
    try std.testing.expect(helper.expressionByIndex(1) == null);
    try std.testing.expectEqual(@as(types.int32, 1), expression.vtable.getNoteExpressionCount(expression, 2, 3));

    var expression_info = ivstnoteexpression.NoteExpressionTypeInfo{};
    try std.testing.expectEqual(types.kResultOk, expression.vtable.getNoteExpressionInfo(expression, 2, 3, 0, &expression_info));
    try std.testing.expectEqual(@intFromEnum(ivstnoteexpression.NoteExpressionTypeIDs.kBrightnessTypeID), expression_info.typeId);
    try std.testing.expectEqual(@as(vsttypes.ParamID, 42), expression_info.associatedParameterId);
    try std.testing.expectEqual(types.kInvalidArgument, expression.vtable.getNoteExpressionInfo(expression, 2, 3, 1, &expression_info));

    try std.testing.expectEqual(types.kResultOk, helper.addKeyswitch(.{
        .typeId = @intFromEnum(ivstnoteexpression.KeyswitchTypeIDs.kNoteOnKeyswitchTypeID),
        .keyswitchMin = 24,
        .keyswitchMax = 36,
        .unitId = 7,
    }));
    try std.testing.expectEqual(types.kResultFalse, helper.addKeyswitch(.{ .typeId = @intFromEnum(ivstnoteexpression.KeyswitchTypeIDs.kOnReleaseKeyswitchTypeID) }));
    try std.testing.expectEqual(@as(types.int32, 24), helper.keyswitchByIndex(0).?.keyswitchMin);
    try std.testing.expect(helper.keyswitchByIndex(1) == null);
    try std.testing.expectEqual(@as(types.int32, 1), keyswitch.vtable.getKeyswitchCount(keyswitch, 4, 5));

    var keyswitch_info = ivstnoteexpression.KeyswitchInfo{};
    try std.testing.expectEqual(types.kResultOk, keyswitch.vtable.getKeyswitchInfo(keyswitch, 4, 5, 0, &keyswitch_info));
    try std.testing.expectEqual(@as(types.int32, 24), keyswitch_info.keyswitchMin);
    try std.testing.expectEqual(@as(types.int32, 36), keyswitch_info.keyswitchMax);
    try std.testing.expectEqual(@as(types.int32, 7), keyswitch_info.unitId);
    try std.testing.expectEqual(types.kInvalidArgument, keyswitch.vtable.getKeyswitchInfo(keyswitch, 4, 5, 1, &keyswitch_info));
}

test "note expression helper rejects appends after inflated counts" {
    const Helper = NoteExpressionController(1, 1, struct {});
    var helper = Helper{};
    helper.expression_count = 99;
    helper.keyswitch_count = 99;

    try std.testing.expectEqual(types.kResultFalse, helper.addExpression(.{}));
    try std.testing.expectEqual(types.kResultFalse, helper.addKeyswitch(.{}));
}

test "note expression helper clears failed outputs" {
    const Helper = NoteExpressionController(1, 1, struct {});
    var helper = Helper{};
    const expression = helper.asNoteExpression();
    const keyswitch = helper.asKeyswitch();

    var expression_info = ivstnoteexpression.NoteExpressionTypeInfo{ .typeId = 99 };
    try std.testing.expectEqual(types.kInvalidArgument, expression.vtable.getNoteExpressionInfo(expression, 0, 1, -1, &expression_info));
    try std.testing.expectEqual(@as(ivstnoteexpression.NoteExpressionTypeID, 0), expression_info.typeId);
    expression_info.typeId = 99;
    try std.testing.expectEqual(types.kInvalidArgument, expression.vtable.getNoteExpressionInfo(expression, 0, 1, 0, &expression_info));
    try std.testing.expectEqual(@as(ivstnoteexpression.NoteExpressionTypeID, 0), expression_info.typeId);

    var text: vsttypes.String128 = [_]vsttypes.TChar{'x'} ** string128.code_units;
    try std.testing.expectEqual(types.kResultFalse, expression.vtable.getNoteExpressionStringByValue(expression, 0, 1, 0, 0.25, &text));
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), text[0]);

    const empty_text: [1:0]vsttypes.TChar = .{0};
    var value: ivstnoteexpression.NoteExpressionValue = 0.5;
    try std.testing.expectEqual(types.kResultFalse, expression.vtable.getNoteExpressionValueByString(expression, 0, 1, 0, &empty_text, &value));
    try std.testing.expectEqual(@as(ivstnoteexpression.NoteExpressionValue, 0), value);

    var keyswitch_info = ivstnoteexpression.KeyswitchInfo{ .typeId = 99 };
    try std.testing.expectEqual(types.kInvalidArgument, keyswitch.vtable.getKeyswitchInfo(keyswitch, 0, 1, -1, &keyswitch_info));
    try std.testing.expectEqual(@as(ivstnoteexpression.KeyswitchTypeID, 0), keyswitch_info.typeId);
}

test "note expression helper delegates string conversions and query interface" {
    const Helper = NoteExpressionController(1, 1, struct {
        pub fn getNoteExpressionStringByValue(_: anytype, _: types.int32, _: types.int16, type_id: ivstnoteexpression.NoteExpressionTypeID, value: ivstnoteexpression.NoteExpressionValue, out: [*]vsttypes.TChar) types.tresult {
            if (type_id != 12 or value != 0.75) return types.kInvalidArgument;
            out[0] = 'O';
            out[1] = 'K';
            out[2] = 0;
            return types.kResultOk;
        }

        pub fn getNoteExpressionValueByString(_: anytype, _: types.int32, _: types.int16, type_id: ivstnoteexpression.NoteExpressionTypeID, text: [*:0]const vsttypes.TChar, out: *ivstnoteexpression.NoteExpressionValue) types.tresult {
            if (type_id != 12 or text[0] != 'O' or text[1] != 'K') return types.kInvalidArgument;
            out.* = 0.75;
            return types.kResultOk;
        }
    });
    var helper = Helper{};
    const expression = helper.asNoteExpression();

    var text: vsttypes.String128 = string128.zero;
    try std.testing.expectEqual(types.kResultOk, expression.vtable.getNoteExpressionStringByValue(expression, 0, 1, 12, 0.75, &text));
    try std.testing.expectEqualSlices(vsttypes.TChar, &.{ 'O', 'K' }, std.mem.sliceTo(&text, 0));

    var value: ivstnoteexpression.NoteExpressionValue = 0;
    try std.testing.expectEqual(types.kResultOk, expression.vtable.getNoteExpressionValueByString(expression, 0, 1, 12, @ptrCast(&text), &value));
    try std.testing.expectEqual(@as(ivstnoteexpression.NoteExpressionValue, 0.75), value);

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, expression.vtable.queryInterface(expression, &ivstnoteexpression.ikeyswitch_controller_iid, &queried));
    try std.testing.expect(queried != null);
    const queried_keyswitch: *ivstnoteexpression.IKeyswitchController = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_keyswitch.vtable.release(queried_keyswitch));
}

test "note expression helper clears unsupported query output from both interfaces" {
    const Helper = NoteExpressionController(1, 1, struct {});
    var helper = Helper{};
    const expression = helper.asNoteExpression();
    const keyswitch = helper.asKeyswitch();

    var queried: ?*anyopaque = @ptrFromInt(0x1000);
    try std.testing.expectEqual(types.kNoInterface, expression.vtable.queryInterface(expression, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);

    queried = @ptrFromInt(0x1000);
    try std.testing.expectEqual(types.kNoInterface, keyswitch.vtable.queryInterface(keyswitch, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
}

test "note expression helper query interfaces share object refcount" {
    const Helper = NoteExpressionController(1, 1, struct {});
    var helper = Helper{};

    var queried_expression: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, helper.asKeyswitch().vtable.queryInterface(helper.asKeyswitch(), &ivstnoteexpression.inote_expression_controller_iid, &queried_expression));
    try std.testing.expectEqual(@as(?*anyopaque, helper.asNoteExpression()), queried_expression);
    try std.testing.expectEqual(@as(types.uint32, 2), helper.ref_count.load(.seq_cst));

    var queried_unknown: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, helper.asKeyswitch().vtable.queryInterface(helper.asKeyswitch(), &funknown.iid, &queried_unknown));
    try std.testing.expectEqual(@as(?*anyopaque, helper.asNoteExpression()), queried_unknown);
    try std.testing.expectEqual(@as(types.uint32, 3), helper.ref_count.load(.seq_cst));

    const expression: *ivstnoteexpression.INoteExpressionController = @ptrCast(@alignCast(queried_expression.?));
    try std.testing.expectEqual(@as(types.uint32, 2), expression.vtable.release(expression));
    try std.testing.expectEqual(@as(types.uint32, 1), helper.asNoteExpression().vtable.release(helper.asNoteExpression()));
}

test "note expression helper clears delegated conversion failures" {
    const Helper = NoteExpressionController(1, 1, struct {
        pub fn getNoteExpressionStringByValue(_: anytype, _: types.int32, _: types.int16, _: ivstnoteexpression.NoteExpressionTypeID, _: ivstnoteexpression.NoteExpressionValue, out: [*]vsttypes.TChar) types.tresult {
            out[0] = 'N';
            out[1] = 'O';
            out[2] = 0;
            return types.kInvalidArgument;
        }

        pub fn getNoteExpressionValueByString(_: anytype, _: types.int32, _: types.int16, _: ivstnoteexpression.NoteExpressionTypeID, _: [*:0]const vsttypes.TChar, out: *ivstnoteexpression.NoteExpressionValue) types.tresult {
            out.* = 0.75;
            return types.kResultFalse;
        }
    });
    var helper = Helper{};
    const expression = helper.asNoteExpression();

    var text: vsttypes.String128 = [_]vsttypes.TChar{'x'} ** string128.code_units;
    try std.testing.expectEqual(types.kInvalidArgument, expression.vtable.getNoteExpressionStringByValue(expression, 0, 0, 1, 0.5, &text));
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), text[0]);
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), text[string128.payload_units]);

    const input_text: [1:0]vsttypes.TChar = .{0};
    var value: ivstnoteexpression.NoteExpressionValue = 0.5;
    try std.testing.expectEqual(types.kResultFalse, expression.vtable.getNoteExpressionValueByString(expression, 0, 0, 1, &input_text, &value));
    try std.testing.expectEqual(@as(ivstnoteexpression.NoteExpressionValue, 0), value);
}
