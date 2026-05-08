const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const ivstparameterchanges = @import("pluginterfaces/vst/ivstparameterchanges.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");

pub const ParamPoint = extern struct {
    sample_offset: types.int32 = 0,
    value: vsttypes.ParamValue = 0,
};

pub fn ParamValueQueue(comptime max_points: usize) type {
    if (max_points == 0) @compileError("ParamValueQueue requires at least one point slot");

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
            if (self.point_count <= 0) return 0;
            return @min(@as(usize, @intCast(self.point_count)), max_points);
        }

        pub fn appendPoint(self: *Self, sample_offset: types.int32, value: vsttypes.ParamValue) types.tresult {
            if (self.point_count < 0 or self.point_count >= max_points) return types.kResultFalse;
            self.points[@intCast(self.point_count)] = .{ .sample_offset = sample_offset, .value = value };
            self.point_count += 1;
            return types.kResultOk;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *ivstparameterchanges.IParamValueQueue = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ivstparameterchanges.iparam_value_queue_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.C) types.uint32 {
            return owner(ptr).ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn release(ptr: *anyopaque) callconv(.C) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IParamValueQueue");
        }

        fn getParameterId(ptr: *anyopaque) callconv(.C) vsttypes.ParamID {
            return owner(ptr).id;
        }

        fn getPointCount(ptr: *anyopaque) callconv(.C) types.int32 {
            return @intCast(owner(ptr).safePointCount());
        }

        fn getPoint(ptr: *anyopaque, index: types.int32, sample_offset: *types.int32, value: *vsttypes.ParamValue) callconv(.C) types.tresult {
            if (index < 0) return types.kInvalidArgument;
            const self = owner(ptr);
            if (@as(usize, @intCast(index)) >= self.safePointCount()) return types.kInvalidArgument;
            const point = self.points[@intCast(index)];
            sample_offset.* = point.sample_offset;
            value.* = point.value;
            return types.kResultOk;
        }

        fn addPoint(ptr: *anyopaque, sample_offset: types.int32, value: vsttypes.ParamValue, index: *types.int32) callconv(.C) types.tresult {
            const self = owner(ptr);
            if (self.point_count < 0 or self.point_count >= max_points) {
                index.* = -1;
                return types.kResultFalse;
            }
            index.* = self.point_count;
            return self.appendPoint(sample_offset, value);
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

pub fn ParameterChanges(comptime max_queues: usize, comptime max_points_per_queue: usize) type {
    if (max_queues == 0) @compileError("ParameterChanges requires at least one parameter queue slot");

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
            if (self.queue_count <= 0) return 0;
            return @min(@as(usize, @intCast(self.queue_count)), max_queues);
        }

        pub fn addQueue(self: *Self, id: vsttypes.ParamID) ?*Queue {
            if (self.queue_count < 0 or self.queue_count >= max_queues) return null;
            const index: usize = @intCast(self.queue_count);
            self.queues[index] = Queue.init(id);
            self.queue_count += 1;
            return &self.queues[index];
        }

        pub fn findQueue(self: *Self, id: vsttypes.ParamID) ?*Queue {
            for (self.queues[0..self.safeQueueCount()]) |*queue| {
                if (queue.id == id) return queue;
            }
            return null;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *ivstparameterchanges.IParameterChanges = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ivstparameterchanges.iparameter_changes_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.C) types.uint32 {
            return owner(ptr).ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn release(ptr: *anyopaque) callconv(.C) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IParameterChanges");
        }

        fn getParameterCount(ptr: *anyopaque) callconv(.C) types.int32 {
            return @intCast(owner(ptr).safeQueueCount());
        }

        fn getParameterData(ptr: *anyopaque, index: types.int32) callconv(.C) ?*ivstparameterchanges.IParamValueQueue {
            if (index < 0) return null;
            const self = owner(ptr);
            if (@as(usize, @intCast(index)) >= self.safeQueueCount()) return null;
            return self.queues[@intCast(index)].asInterface();
        }

        fn addParameterData(ptr: *anyopaque, id: *const vsttypes.ParamID, index: *types.int32) callconv(.C) ?*ivstparameterchanges.IParamValueQueue {
            const self = owner(ptr);
            for (self.queues[0..self.safeQueueCount()], 0..) |*queue, queue_index| {
                if (queue.id == id.*) {
                    index.* = @intCast(queue_index);
                    return queue.asInterface();
                }
            }
            const queue = self.addQueue(id.*) orelse {
                index.* = -1;
                return null;
            };
            index.* = self.queue_count - 1;
            return queue.asInterface();
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

    const iface = changes.asInterface();
    try std.testing.expectEqual(@as(types.int32, 1), iface.vtable.getParameterCount(iface));
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
    try std.testing.expectEqual(@as(types.int32, 99), sample_offset);
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 99), value);
    try std.testing.expectEqual(types.kInvalidArgument, queue_iface.vtable.getPoint(queue_iface, 2, &sample_offset, &value));
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
    try std.testing.expectEqual(types.kResultFalse, queue_iface.vtable.addPoint(queue_iface, 0, 0.5, &point_index));
    try std.testing.expectEqual(@as(types.int32, -1), point_index);

    queue.point_count = 2;
    try std.testing.expectEqual(@as(types.int32, 1), queue_iface.vtable.getPointCount(queue_iface));
    try std.testing.expectEqual(types.kResultFalse, queue_iface.vtable.addPoint(queue_iface, 0, 0.5, &point_index));
}
