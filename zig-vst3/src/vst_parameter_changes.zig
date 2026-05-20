const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const ivstparameterchanges = @import("pluginterfaces/vst/ivstparameterchanges.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const vst_index = @import("vst_index.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");

pub const ParamPoint = extern struct {
    sample_offset: types.int32 = 0,
    value: vsttypes.ParamValue = 0,
};

pub fn ParamValueQueue(comptime max_points: usize) type {
    if (max_points == 0) @compileError("ParamValueQueue requires at least one point slot");
    vst_index.requireInt32Capacity(max_points, "ParamValueQueue capacity");

    return extern struct {
        const Self = @This();

        iface: ivstparameterchanges.IParamValueQueue = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        id: vsttypes.ParamID = 0,
        points: [max_points]ParamPoint = [_]ParamPoint{.{}} ** max_points,
        point_count: types.int32 = 0,

        pub fn init(id: vsttypes.ParamID) Self {
            return .{ .id = id };
        }

        pub fn asInterface(self: *Self) *ivstparameterchanges.IParamValueQueue {
            return &self.iface;
        }

        fn safePointCount(self: *const Self) usize {
            return vst_index.clampedCount(self.point_count, max_points);
        }

        fn appendPointIndex(self: *Self, sample_offset: types.int32, value: vsttypes.ParamValue) ?types.int32 {
            if (sample_offset < 0) return null;
            if (!isNormalized(value)) return null;
            const index = vst_index.appendIndex(self.point_count, max_points) orelse return null;
            self.points[index] = .{ .sample_offset = sample_offset, .value = value };
            self.point_count +|= 1;
            return @intCast(index);
        }

        pub fn appendPoint(self: *Self, sample_offset: types.int32, value: vsttypes.ParamValue) types.tresult {
            _ = self.appendPointIndex(sample_offset, value) orelse return types.kResultFalse;
            return types.kResultOk;
        }

        pub fn pointByIndex(self: *const Self, index: types.int32) ?ParamPoint {
            const point_index = vst_index.bounded(index, self.safePointCount()) orelse return null;
            return self.points[point_index];
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *ivstparameterchanges.IParamValueQueue = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ivstparameterchanges.iparam_value_queue_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IParamValueQueue");
        }

        fn getParameterId(ptr: *anyopaque) callconv(.c) vsttypes.ParamID {
            return owner(ptr).id;
        }

        fn getPointCount(ptr: *anyopaque) callconv(.c) types.int32 {
            return @intCast(owner(ptr).safePointCount());
        }

        fn failPoint(sample_offset: *types.int32, value: *vsttypes.ParamValue) types.tresult {
            sample_offset.* = 0;
            value.* = 0;
            return types.kInvalidArgument;
        }

        fn getPoint(ptr: *anyopaque, index: types.int32, sample_offset: *types.int32, value: *vsttypes.ParamValue) callconv(.c) types.tresult {
            const self = owner(ptr);
            const point = self.pointByIndex(index) orelse return failPoint(sample_offset, value);
            sample_offset.* = point.sample_offset;
            value.* = point.value;
            return types.kResultOk;
        }

        fn failAddedPoint(index: *types.int32) types.tresult {
            index.* = -1;
            return types.kResultFalse;
        }

        fn addPoint(ptr: *anyopaque, sample_offset: types.int32, value: vsttypes.ParamValue, index: *types.int32) callconv(.c) types.tresult {
            const self = owner(ptr);
            index.* = self.appendPointIndex(sample_offset, value) orelse return failAddedPoint(index);
            return types.kResultOk;
        }

        const vtable = ivstparameterchanges.IParamValueQueueVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .getParameterId = getParameterId,
            .getPointCount = getPointCount,
            .getPoint = getPoint,
            .addPoint = addPoint,
        };
    };
}

fn isNormalized(value: vsttypes.ParamValue) bool {
    return std.math.isFinite(value) and value >= 0.0 and value <= 1.0;
}

pub fn ParameterChanges(comptime max_queues: usize, comptime max_points_per_queue: usize) type {
    if (max_queues == 0) @compileError("ParameterChanges requires at least one parameter queue slot");
    vst_index.requireInt32Capacity(max_queues, "ParameterChanges capacity");

    return extern struct {
        const Self = @This();
        const Queue = ParamValueQueue(max_points_per_queue);

        iface: ivstparameterchanges.IParameterChanges = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        queues: [max_queues]Queue = [_]Queue{.{}} ** max_queues,
        queue_count: types.int32 = 0,

        pub fn asInterface(self: *Self) *ivstparameterchanges.IParameterChanges {
            return &self.iface;
        }

        fn safeQueueCount(self: *const Self) usize {
            return vst_index.clampedCount(self.queue_count, max_queues);
        }

        fn addQueueIndex(self: *Self, id: vsttypes.ParamID) ?usize {
            const index = vst_index.appendIndex(self.queue_count, max_queues) orelse return null;
            self.queues[index] = Queue.init(id);
            self.queue_count +|= 1;
            return index;
        }

        pub fn addQueue(self: *Self, id: vsttypes.ParamID) ?*Queue {
            const index = self.addQueueIndex(id) orelse return null;
            return &self.queues[index];
        }

        pub fn findQueue(self: *Self, id: vsttypes.ParamID) ?*Queue {
            const index = self.findQueueIndex(id) orelse return null;
            return &self.queues[index];
        }

        pub fn findQueueIndex(self: *Self, id: vsttypes.ParamID) ?usize {
            for (self.queues[0..self.safeQueueCount()], 0..) |*queue, queue_index| {
                if (queue.id == id) return queue_index;
            }
            return null;
        }

        pub fn queueByIndex(self: *Self, index: types.int32) ?*Queue {
            const queue_index = vst_index.bounded(index, self.safeQueueCount()) orelse return null;
            return &self.queues[queue_index];
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *ivstparameterchanges.IParameterChanges = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ivstparameterchanges.iparameter_changes_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IParameterChanges");
        }

        fn getParameterCount(ptr: *anyopaque) callconv(.c) types.int32 {
            return @intCast(owner(ptr).safeQueueCount());
        }

        fn getParameterData(ptr: *anyopaque, index: types.int32) callconv(.c) ?*ivstparameterchanges.IParamValueQueue {
            const self = owner(ptr);
            const queue = self.queueByIndex(index) orelse return null;
            return queue.asInterface();
        }

        fn failAddedParameterData(index: *types.int32) ?*ivstparameterchanges.IParamValueQueue {
            index.* = -1;
            return null;
        }

        fn addParameterData(ptr: *anyopaque, id: *const vsttypes.ParamID, index: *types.int32) callconv(.c) ?*ivstparameterchanges.IParamValueQueue {
            const self = owner(ptr);
            if (self.findQueueIndex(id.*)) |queue_index| {
                index.* = @intCast(queue_index);
                return self.queues[queue_index].asInterface();
            }
            const queue_index = self.addQueueIndex(id.*) orelse return failAddedParameterData(index);
            index.* = @intCast(queue_index);
            return self.queues[queue_index].asInterface();
        }

        const vtable = ivstparameterchanges.IParameterChangesVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .getParameterCount = getParameterCount,
            .getParameterData = getParameterData,
            .addParameterData = addParameterData,
        };
    };
}

test "parameter changes expose queued points" {
    const Changes = ParameterChanges(2, 3);
    var changes = Changes{};
    const queue = changes.addQueue(7).?;
    try std.testing.expectEqual(types.kResultOk, queue.appendPoint(0, 0.25));
    try std.testing.expectEqual(types.kResultOk, queue.appendPoint(3, 0.75));
    try std.testing.expectEqual(@as(types.int32, 3), queue.pointByIndex(1).?.sample_offset);
    try std.testing.expectEqual(@as(?ParamPoint, null), queue.pointByIndex(2));

    const iface = changes.asInterface();
    try std.testing.expectEqual(@as(types.int32, 1), iface.vtable.getParameterCount(iface));
    try std.testing.expect(changes.queueByIndex(0).?.asInterface() == queue.asInterface());
    try std.testing.expect(changes.queueByIndex(1) == null);
    const queue_iface = iface.vtable.getParameterData(iface, 0).?;
    try std.testing.expectEqual(@as(vsttypes.ParamID, 7), queue_iface.vtable.getParameterId(queue_iface));
    try std.testing.expectEqual(@as(types.int32, 2), queue_iface.vtable.getPointCount(queue_iface));

    var sample_offset: types.int32 = -1;
    var value: vsttypes.ParamValue = -1;
    try std.testing.expectEqual(types.kResultOk, queue_iface.vtable.getPoint(queue_iface, 1, &sample_offset, &value));
    try std.testing.expectEqual(@as(types.int32, 3), sample_offset);
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.75), value);

    sample_offset = 99;
    value = 99;
    try std.testing.expectEqual(types.kInvalidArgument, queue_iface.vtable.getPoint(queue_iface, -1, &sample_offset, &value));
    try std.testing.expectEqual(@as(types.int32, 0), sample_offset);
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0), value);
    sample_offset = 99;
    value = 99;
    try std.testing.expectEqual(types.kInvalidArgument, queue_iface.vtable.getPoint(queue_iface, 2, &sample_offset, &value));
    try std.testing.expectEqual(@as(types.int32, 0), sample_offset);
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0), value);
    try std.testing.expect(iface.vtable.getParameterData(iface, -1) == null);
    try std.testing.expect(iface.vtable.getParameterData(iface, 1) == null);
}

test "parameter changes add parameter data and support query interface" {
    const Changes = ParameterChanges(1, 1);
    var changes = Changes{};
    const iface = changes.asInterface();
    var id: vsttypes.ParamID = 9;
    var index: types.int32 = -1;
    const queue_iface = iface.vtable.addParameterData(iface, &id, &index).?;

    try std.testing.expectEqual(@as(types.int32, 0), index);
    var point_index: types.int32 = -1;
    try std.testing.expectEqual(types.kResultOk, queue_iface.vtable.addPoint(queue_iface, 2, 0.5, &point_index));
    try std.testing.expectEqual(@as(types.int32, 0), point_index);
    point_index = 42;
    try std.testing.expectEqual(types.kResultFalse, queue_iface.vtable.addPoint(queue_iface, 3, 0.75, &point_index));
    try std.testing.expectEqual(@as(types.int32, -1), point_index);
    try std.testing.expect(iface.vtable.addParameterData(iface, &id, &index) != null);

    var other_id: vsttypes.ParamID = 10;
    index = 42;
    try std.testing.expect(iface.vtable.addParameterData(iface, &other_id, &index) == null);
    try std.testing.expectEqual(@as(types.int32, -1), index);

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &ivstparameterchanges.iparameter_changes_iid, &queried));
    try std.testing.expect(queried != null);
    const queried_changes: *ivstparameterchanges.IParameterChanges = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_changes.vtable.release(queried_changes));
}

test "parameter changes reuse existing queues by id" {
    const Changes = ParameterChanges(2, 2);
    var changes = Changes{};
    const iface = changes.asInterface();
    var id: vsttypes.ParamID = 9;
    var first_index: types.int32 = -1;
    var second_index: types.int32 = -1;

    const first_queue = iface.vtable.addParameterData(iface, &id, &first_index).?;
    const second_queue = iface.vtable.addParameterData(iface, &id, &second_index).?;
    try std.testing.expectEqual(@as(types.int32, 0), first_index);
    try std.testing.expectEqual(@as(types.int32, 0), second_index);
    try std.testing.expectEqual(@as(types.int32, 1), iface.vtable.getParameterCount(iface));
    try std.testing.expect(first_queue == second_queue);
    try std.testing.expectEqual(@as(?usize, 0), changes.findQueueIndex(id));
    try std.testing.expect(changes.findQueue(id).?.asInterface() == first_queue);
    try std.testing.expectEqual(@as(?usize, null), changes.findQueueIndex(10));
    try std.testing.expect(changes.findQueue(10) == null);

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, first_queue.vtable.queryInterface(first_queue, &ivstparameterchanges.iparam_value_queue_iid, &queried));
    try std.testing.expect(queried != null);
    const queried_queue: *ivstparameterchanges.IParamValueQueue = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_queue.vtable.release(queried_queue));
}

test "parameter value queue preserves contents when full" {
    var queue = ParamValueQueue(1).init(7);
    const iface = queue.asInterface();
    var first_index: types.int32 = -1;
    var rejected_index: types.int32 = 42;

    try std.testing.expectEqual(types.kResultOk, iface.vtable.addPoint(iface, 12, 0.25, &first_index));
    try std.testing.expectEqual(@as(types.int32, 0), first_index);
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.addPoint(iface, 24, 0.75, &rejected_index));
    try std.testing.expectEqual(@as(types.int32, -1), rejected_index);
    try std.testing.expectEqual(@as(types.int32, 1), iface.vtable.getPointCount(iface));

    var sample_offset: types.int32 = -1;
    var value: vsttypes.ParamValue = -1;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getPoint(iface, 0, &sample_offset, &value));
    try std.testing.expectEqual(@as(types.int32, 12), sample_offset);
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.25), value);
}

test "parameter value queue rejects invalid points" {
    var queue = ParamValueQueue(2).init(7);
    const iface = queue.asInterface();
    var index: types.int32 = 42;

    try std.testing.expectEqual(types.kResultFalse, iface.vtable.addPoint(iface, -1, 0.5, &index));
    try std.testing.expectEqual(@as(types.int32, -1), index);
    try std.testing.expectEqual(@as(types.int32, 0), iface.vtable.getPointCount(iface));

    index = 42;
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.addPoint(iface, 0, -0.01, &index));
    try std.testing.expectEqual(@as(types.int32, -1), index);

    index = 42;
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.addPoint(iface, 0, 1.01, &index));
    try std.testing.expectEqual(@as(types.int32, -1), index);

    index = 42;
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.addPoint(iface, 0, std.math.inf(vsttypes.ParamValue), &index));
    try std.testing.expectEqual(@as(types.int32, -1), index);

    index = 42;
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.addPoint(iface, 0, std.math.nan(vsttypes.ParamValue), &index));
    try std.testing.expectEqual(@as(types.int32, -1), index);

    index = 42;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.addPoint(iface, 0, 1.0, &index));
    try std.testing.expectEqual(@as(types.int32, 0), index);
    try std.testing.expectEqual(@as(types.int32, 1), iface.vtable.getPointCount(iface));
}

test "parameter changes clear unsupported query outputs" {
    const Changes = ParameterChanges(1, 1);
    var changes = Changes{};
    const iface = changes.asInterface();
    var id: vsttypes.ParamID = 9;
    var index: types.int32 = -1;
    const queue_iface = iface.vtable.addParameterData(iface, &id, &index).?;

    var queried: ?*anyopaque = @ptrFromInt(0x1000);
    try std.testing.expectEqual(types.kNoInterface, iface.vtable.queryInterface(iface, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);

    queried = @ptrFromInt(0x1000);
    try std.testing.expectEqual(types.kNoInterface, queue_iface.vtable.queryInterface(queue_iface, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
}

test "parameter changes clamp corrupted counts" {
    const Changes = ParameterChanges(1, 1);
    var changes = Changes{};
    const iface = changes.asInterface();
    var id: vsttypes.ParamID = 9;
    var index: types.int32 = 42;

    changes.queue_count = -1;
    try std.testing.expectEqual(@as(types.int32, 0), iface.vtable.getParameterCount(iface));
    try std.testing.expect(iface.vtable.getParameterData(iface, 0) == null);
    try std.testing.expect(iface.vtable.addParameterData(iface, &id, &index) == null);
    try std.testing.expectEqual(@as(types.int32, -1), index);

    changes.queue_count = 2;
    try std.testing.expectEqual(@as(types.int32, 1), iface.vtable.getParameterCount(iface));
    try std.testing.expect(iface.vtable.addParameterData(iface, &id, &index) == null);

    var queue = ParamValueQueue(1).init(7);
    const queue_iface = queue.asInterface();
    var sample_offset: types.int32 = 99;
    var value: vsttypes.ParamValue = 99;
    var point_index: types.int32 = 42;

    queue.point_count = -1;
    try std.testing.expectEqual(@as(types.int32, 0), queue_iface.vtable.getPointCount(queue_iface));
    try std.testing.expectEqual(types.kInvalidArgument, queue_iface.vtable.getPoint(queue_iface, 0, &sample_offset, &value));
    try std.testing.expectEqual(@as(types.int32, 0), sample_offset);
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0), value);
    try std.testing.expectEqual(types.kResultFalse, queue_iface.vtable.addPoint(queue_iface, 0, 0.5, &point_index));
    try std.testing.expectEqual(@as(types.int32, -1), point_index);

    queue.point_count = 2;
    try std.testing.expectEqual(@as(types.int32, 1), queue_iface.vtable.getPointCount(queue_iface));
    try std.testing.expectEqual(types.kResultFalse, queue_iface.vtable.addPoint(queue_iface, 0, 0.5, &point_index));
}
