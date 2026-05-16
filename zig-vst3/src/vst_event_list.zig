const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const ivstevents = @import("pluginterfaces/vst/ivstevents.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");

fn boundedIndex(index: types.int32, count: usize) ?usize {
    if (index < 0) return null;
    const value: usize = @intCast(index);
    return if (value < count) value else null;
}

pub fn EventList(comptime max_events: usize) type {
    if (max_events == 0) @compileError("EventList requires at least one event slot");
    if (max_events > std.math.maxInt(types.int32)) @compileError("EventList capacity must fit in VST int32 counts");

    return extern struct {
        const Self = @This();

        iface: ivstevents.IEventList = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        events: [max_events]ivstevents.Event = [_]ivstevents.Event{.{}} ** max_events,
        count: types.int32 = 0,
        fail_get_index: types.int32 = -1,
        fail_add_index: types.int32 = -1,

        pub fn asInterface(self: *Self) *ivstevents.IEventList {
            return &self.iface;
        }

        fn safeCount(self: *const Self) usize {
            if (self.count <= 0) return 0;
            return @min(@as(usize, @intCast(self.count)), max_events);
        }

        pub fn append(self: *Self, event: ivstevents.Event) types.tresult {
            if (self.count < 0 or self.count >= max_events) return types.kResultFalse;
            self.events[@intCast(self.count)] = event;
            self.count +|= 1;
            return types.kResultOk;
        }

        pub fn items(self: *const Self) []const ivstevents.Event {
            return self.events[0..self.safeCount()];
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *ivstevents.IEventList = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ivstevents.ievent_list_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IEventList");
        }

        fn getEventCount(ptr: *anyopaque) callconv(.c) types.int32 {
            return @intCast(owner(ptr).safeCount());
        }

        fn getEvent(ptr: *anyopaque, index: types.int32, event: *ivstevents.Event) callconv(.c) types.tresult {
            if (index < 0) {
                event.* = .{};
                return types.kInvalidArgument;
            }
            const self = owner(ptr);
            if (index == self.fail_get_index) {
                event.* = .{};
                return types.kResultFalse;
            }
            const event_index = boundedIndex(index, self.safeCount()) orelse {
                event.* = .{};
                return types.kInvalidArgument;
            };
            event.* = self.events[event_index];
            return types.kResultOk;
        }

        fn addEvent(ptr: *anyopaque, event: *ivstevents.Event) callconv(.c) types.tresult {
            const self = owner(ptr);
            if (self.count == self.fail_add_index) return types.kResultFalse;
            return self.append(event.*);
        }

        const vtable = ivstevents.IEventListVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .getEventCount = getEventCount,
            .getEvent = getEvent,
            .addEvent = addEvent,
        };
    };
}

test "event list reads and writes events" {
    const List = EventList(2);
    var list = List{};
    const iface = list.asInterface();
    var event = ivstevents.Event{
        .sampleOffset = 3,
        .type = @intFromEnum(ivstevents.Event.EventTypes.kNoteOnEvent),
        .data = .{ .noteOn = .{ .pitch = 60, .velocity = 0.5 } },
    };

    try std.testing.expectEqual(types.kResultOk, iface.vtable.addEvent(iface, &event));
    try std.testing.expectEqual(@as(types.int32, 1), iface.vtable.getEventCount(iface));

    var read_event = ivstevents.Event{};
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getEvent(iface, 0, &read_event));
    try std.testing.expectEqual(@as(types.int32, 3), read_event.sampleOffset);
    try std.testing.expectEqual(@as(types.int16, 60), read_event.data.noteOn.pitch);
}

test "event list enforces bounds and supports query interface" {
    const List = EventList(1);
    var list = List{};
    const iface = list.asInterface();
    var event = ivstevents.Event{};

    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.getEvent(iface, 0, &event));
    try std.testing.expectEqual(@as(types.int32, 0), event.sampleOffset);
    try std.testing.expectEqual(types.kResultOk, iface.vtable.addEvent(iface, &event));
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.addEvent(iface, &event));

    event.sampleOffset = 99;
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.getEvent(iface, -1, &event));
    try std.testing.expectEqual(@as(types.int32, 0), event.sampleOffset);

    event.sampleOffset = 99;
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.getEvent(iface, 1, &event));
    try std.testing.expectEqual(@as(types.int32, 0), event.sampleOffset);

    event.sampleOffset = 99;
    list.fail_get_index = 0;
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.getEvent(iface, 0, &event));
    try std.testing.expectEqual(@as(types.int32, 0), event.sampleOffset);

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &ivstevents.ievent_list_iid, &queried));
    try std.testing.expect(queried != null);
    const queried_events: *ivstevents.IEventList = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_events.vtable.release(queried_events));
}

test "event list preserves count when add event is configured to fail" {
    const List = EventList(2);
    var list = List{ .fail_add_index = 1 };
    const iface = list.asInterface();
    var first_event = ivstevents.Event{ .sampleOffset = 1 };
    var second_event = ivstevents.Event{ .sampleOffset = 2 };

    try std.testing.expectEqual(types.kResultOk, iface.vtable.addEvent(iface, &first_event));
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.addEvent(iface, &second_event));
    try std.testing.expectEqual(@as(types.int32, 1), iface.vtable.getEventCount(iface));

    var read_event = ivstevents.Event{};
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getEvent(iface, 0, &read_event));
    try std.testing.expectEqual(@as(types.int32, 1), read_event.sampleOffset);
}

test "event list clamps corrupted counts" {
    const List = EventList(1);
    var list = List{};
    const iface = list.asInterface();
    var event = ivstevents.Event{ .sampleOffset = 99 };

    list.count = -1;
    try std.testing.expectEqual(@as(types.int32, 0), iface.vtable.getEventCount(iface));
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.addEvent(iface, &event));
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.getEvent(iface, 0, &event));
    try std.testing.expectEqual(@as(types.int32, 0), event.sampleOffset);

    list.count = 2;
    try std.testing.expectEqual(@as(types.int32, 1), iface.vtable.getEventCount(iface));
    try std.testing.expectEqual(@as(usize, 1), list.items().len);
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.addEvent(iface, &event));
}
