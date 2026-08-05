const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const ivstevents = @import("pluginterfaces/vst/ivstevents.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const vst_index = @import("vst_index.zig");

pub fn EventList(comptime max_events: usize) type {
    if (max_events == 0) @compileError("EventList requires at least one event slot");
    vst_index.requireInt32Capacity(max_events, "EventList capacity");

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
            return vst_index.clampedCount(self.count, max_events);
        }

        fn appendIndex(self: *Self, event: ivstevents.Event) ?usize {
            const index = vst_index.appendIndex(self.count, max_events) orelse return null;
            self.events[index] = event;
            self.count = vst_index.int32NextCount(index);
            return index;
        }

        pub fn append(self: *Self, event: ivstevents.Event) types.tresult {
            _ = self.appendIndex(event) orelse return types.kResultFalse;
            return types.kResultOk;
        }

        pub fn items(self: *const Self) []const ivstevents.Event {
            return self.events[0..self.safeCount()];
        }

        pub fn eventByIndex(self: *const Self, index: types.int32) ?ivstevents.Event {
            const event_index = vst_index.bounded(index, self.safeCount()) orelse return null;
            return self.events[event_index];
        }

        const owner = interface_map.ownerFromField(Self, ivstevents.IEventList, "iface");

        fn query(ptr: *anyopaque, requested_iid: [*c]const tuid.TUID, out: [*c]?*anyopaque) callconv(.c) types.tresult {
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
            return vst_index.int32Count(owner(ptr).safeCount());
        }

        fn failEvent(event: *ivstevents.Event, result: types.tresult) types.tresult {
            event.* = .{};
            return result;
        }

        fn getEvent(ptr: *anyopaque, index: types.int32, event_raw: [*c]ivstevents.Event) callconv(.c) types.tresult {
            if (event_raw == null) return types.kInvalidArgument;
            const event: *ivstevents.Event = @ptrCast(event_raw);
            if (index < 0) return failEvent(event, types.kInvalidArgument);
            const self = owner(ptr);
            if (index == self.fail_get_index) return failEvent(event, types.kResultFalse);
            event.* = self.eventByIndex(index) orelse return failEvent(event, types.kInvalidArgument);
            return types.kResultOk;
        }

        fn addEvent(ptr: *anyopaque, event: [*c]ivstevents.Event) callconv(.c) types.tresult {
            if (event == null) return types.kInvalidArgument;
            const self = owner(ptr);
            if (self.count == self.fail_add_index) return types.kResultFalse;
            return self.append(event[0]);
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
    try std.testing.expectEqual(@as(types.int32, 3), list.eventByIndex(0).?.sampleOffset);
    try std.testing.expect(list.eventByIndex(1) == null);

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

    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.getEvent(iface, 0, null));
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.addEvent(iface, null));
    try std.testing.expectEqual(@as(types.int32, 0), iface.vtable.getEventCount(iface));

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

    queried = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &funknown.iid, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, iface), queried);
    try std.testing.expectEqual(@as(types.uint32, 2), list.ref_count.load(.seq_cst));
    const queried_unknown: *ivstevents.IEventList = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_unknown.vtable.release(queried_unknown));
}

test "event list clears unsupported query output" {
    const List = EventList(1);
    var list = List{};
    const iface = list.asInterface();

    var queried: ?*anyopaque = @ptrFromInt(0x1000);
    try std.testing.expectEqual(types.kNoInterface, iface.vtable.queryInterface(iface, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
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
