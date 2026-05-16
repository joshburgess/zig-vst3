const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const iplugview = @import("pluginterfaces/gui/iplugview.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");

const Linux = iplugview.Linux;

pub fn EventHandler(comptime Config: type) type {
    return extern struct {
        const Self = @This();

        iface: Linux.IEventHandler = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        last_fd: Linux.FileDescriptor = -1,
        event_count: types.uint32 = 0,

        pub fn asInterface(self: *Self) *Linux.IEventHandler {
            return &self.iface;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *Linux.IEventHandler = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &iplugview.ievent_handler_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IEventHandler");
        }

        fn onFDIsSet(ptr: *anyopaque, fd: Linux.FileDescriptor) callconv(.c) void {
            const self = owner(ptr);
            self.last_fd = fd;
            self.event_count +|= 1;
            if (@hasDecl(Config, "onFDIsSet")) {
                Config.onFDIsSet(fd);
            }
        }

        const vtable = Linux.IEventHandlerVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .onFDIsSet = onFDIsSet,
        };
    };
}

pub fn TimerHandler(comptime Config: type) type {
    return extern struct {
        const Self = @This();

        iface: Linux.ITimerHandler = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        timer_count: types.uint32 = 0,

        pub fn asInterface(self: *Self) *Linux.ITimerHandler {
            return &self.iface;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *Linux.ITimerHandler = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &iplugview.itimer_handler_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "ITimerHandler");
        }

        fn onTimer(ptr: *anyopaque) callconv(.c) void {
            const self = owner(ptr);
            self.timer_count +|= 1;
            if (@hasDecl(Config, "onTimer")) {
                Config.onTimer();
            }
        }

        const vtable = Linux.ITimerHandlerVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .onTimer = onTimer,
        };
    };
}

pub fn RunLoop(comptime max_event_handlers: usize, comptime max_timer_handlers: usize) type {
    if (max_event_handlers == 0) @compileError("RunLoop requires at least one event-handler slot");
    if (max_timer_handlers == 0) @compileError("RunLoop requires at least one timer-handler slot");

    return extern struct {
        const Self = @This();

        const EventEntry = extern struct {
            handler: ?*Linux.IEventHandler = null,
            fd: Linux.FileDescriptor = -1,
        };

        const TimerEntry = extern struct {
            handler: ?*Linux.ITimerHandler = null,
            interval: Linux.TimerInterval = 0,
        };

        iface: Linux.IRunLoop = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        event_handlers: [max_event_handlers]EventEntry = [_]EventEntry{.{}} ** max_event_handlers,
        timer_handlers: [max_timer_handlers]TimerEntry = [_]TimerEntry{.{}} ** max_timer_handlers,

        pub fn asInterface(self: *Self) *Linux.IRunLoop {
            return &self.iface;
        }

        pub fn triggerEvent(self: *Self, fd: Linux.FileDescriptor) types.tresult {
            for (&self.event_handlers) |*entry| {
                if (entry.handler != null and entry.fd == fd) {
                    entry.handler.?.vtable.onFDIsSet(entry.handler.?, fd);
                    return types.kResultOk;
                }
            }
            return types.kResultFalse;
        }

        pub fn triggerTimer(self: *Self, handler: *Linux.ITimerHandler) types.tresult {
            for (&self.timer_handlers) |*entry| {
                if (entry.handler == handler) {
                    handler.vtable.onTimer(handler);
                    return types.kResultOk;
                }
            }
            return types.kResultFalse;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *Linux.IRunLoop = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &iplugview.irun_loop_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IRunLoop");
        }

        fn registerEventHandler(ptr: *anyopaque, handler: ?*Linux.IEventHandler, fd: Linux.FileDescriptor) callconv(.c) types.tresult {
            const event_handler = handler orelse return types.kInvalidArgument;
            if (fd < 0) return types.kInvalidArgument;
            const self = owner(ptr);
            for (&self.event_handlers) |*entry| {
                if (entry.handler == event_handler) {
                    entry.fd = fd;
                    return types.kResultOk;
                }
            }
            for (&self.event_handlers) |*entry| {
                if (entry.handler == null) {
                    entry.handler = event_handler;
                    entry.fd = fd;
                    _ = event_handler.vtable.addRef(event_handler);
                    return types.kResultOk;
                }
            }
            return types.kResultFalse;
        }

        fn unregisterEventHandler(ptr: *anyopaque, handler: ?*Linux.IEventHandler) callconv(.c) types.tresult {
            const event_handler = handler orelse return types.kInvalidArgument;
            for (&owner(ptr).event_handlers) |*entry| {
                if (entry.handler == event_handler) {
                    entry.* = .{};
                    _ = event_handler.vtable.release(event_handler);
                    return types.kResultOk;
                }
            }
            return types.kResultFalse;
        }

        fn registerTimer(ptr: *anyopaque, handler: ?*Linux.ITimerHandler, interval: Linux.TimerInterval) callconv(.c) types.tresult {
            const timer_handler = handler orelse return types.kInvalidArgument;
            const self = owner(ptr);
            for (&self.timer_handlers) |*entry| {
                if (entry.handler == timer_handler) {
                    entry.interval = interval;
                    return types.kResultOk;
                }
            }
            for (&self.timer_handlers) |*entry| {
                if (entry.handler == null) {
                    entry.handler = timer_handler;
                    entry.interval = interval;
                    _ = timer_handler.vtable.addRef(timer_handler);
                    return types.kResultOk;
                }
            }
            return types.kResultFalse;
        }

        fn unregisterTimer(ptr: *anyopaque, handler: ?*Linux.ITimerHandler) callconv(.c) types.tresult {
            const timer_handler = handler orelse return types.kInvalidArgument;
            for (&owner(ptr).timer_handlers) |*entry| {
                if (entry.handler == timer_handler) {
                    entry.* = .{};
                    _ = timer_handler.vtable.release(timer_handler);
                    return types.kResultOk;
                }
            }
            return types.kResultFalse;
        }

        const vtable = Linux.IRunLoopVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .registerEventHandler = registerEventHandler,
            .unregisterEventHandler = unregisterEventHandler,
            .registerTimer = registerTimer,
            .unregisterTimer = unregisterTimer,
        };
    };
}

test "linux run loop registers and triggers event handlers" {
    const Loop = RunLoop(1, 1);
    const Handler = EventHandler(struct {});
    var loop = Loop{};
    var handler = Handler{};
    const iface = loop.asInterface();
    const event_handler = handler.asInterface();

    try std.testing.expectEqual(types.kResultOk, iface.vtable.registerEventHandler(iface, event_handler, 7));
    try std.testing.expectEqual(@as(types.uint32, 2), handler.ref_count.load(.monotonic));
    try std.testing.expectEqual(types.kResultOk, loop.triggerEvent(7));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.event_count);
    try std.testing.expectEqual(@as(Linux.FileDescriptor, 7), handler.last_fd);
    try std.testing.expectEqual(types.kResultOk, iface.vtable.unregisterEventHandler(iface, event_handler));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.ref_count.load(.monotonic));
}

test "linux event and timer handlers delegate callbacks and support query interface" {
    const Event = EventHandler(struct {
        var last_fd: Linux.FileDescriptor = -1;

        pub fn onFDIsSet(fd: Linux.FileDescriptor) void {
            last_fd = fd;
        }
    });
    const Timer = TimerHandler(struct {
        var count: types.uint32 = 0;

        pub fn onTimer() void {
            count += 1;
        }
    });
    var event = Event{};
    var timer = Timer{};

    event.asInterface().vtable.onFDIsSet(event.asInterface(), 12);
    timer.asInterface().vtable.onTimer(timer.asInterface());
    try std.testing.expectEqual(@as(Linux.FileDescriptor, 12), event.last_fd);
    try std.testing.expectEqual(@as(Linux.FileDescriptor, 12), Event.last_fd);
    try std.testing.expectEqual(@as(types.uint32, 1), timer.timer_count);
    try std.testing.expectEqual(@as(types.uint32, 1), Timer.count);

    var event_query: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, event.asInterface().vtable.queryInterface(event.asInterface(), &iplugview.ievent_handler_iid, &event_query));
    try std.testing.expect(event_query != null);
    const queried_event: *Linux.IEventHandler = @ptrCast(@alignCast(event_query.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_event.vtable.release(queried_event));

    var timer_query: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, timer.asInterface().vtable.queryInterface(timer.asInterface(), &iplugview.itimer_handler_iid, &timer_query));
    try std.testing.expect(timer_query != null);
    const queried_timer: *Linux.ITimerHandler = @ptrCast(@alignCast(timer_query.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_timer.vtable.release(queried_timer));
}

test "linux run loop updates duplicate event registrations without extra retain" {
    const Loop = RunLoop(1, 1);
    const Handler = EventHandler(struct {});
    var loop = Loop{};
    var handler = Handler{};
    const iface = loop.asInterface();
    const event_handler = handler.asInterface();

    try std.testing.expectEqual(types.kResultOk, iface.vtable.registerEventHandler(iface, event_handler, 7));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.registerEventHandler(iface, event_handler, 9));
    try std.testing.expectEqual(@as(types.uint32, 2), handler.ref_count.load(.monotonic));
    try std.testing.expectEqual(types.kResultFalse, loop.triggerEvent(7));
    try std.testing.expectEqual(types.kResultOk, loop.triggerEvent(9));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.unregisterEventHandler(iface, event_handler));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.ref_count.load(.monotonic));
}

test "linux run loop rejects invalid event handler registrations" {
    const Loop = RunLoop(1, 1);
    const Handler = EventHandler(struct {});
    var loop = Loop{};
    var handler = Handler{};
    const iface = loop.asInterface();
    const event_handler = handler.asInterface();

    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.registerEventHandler(iface, null, 7));
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.registerEventHandler(iface, event_handler, -1));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.ref_count.load(.monotonic));
}

test "linux run loop rejects full event handler storage and missing unregisters" {
    const Loop = RunLoop(1, 1);
    const Handler = EventHandler(struct {});
    var loop = Loop{};
    var first = Handler{};
    var second = Handler{};
    const iface = loop.asInterface();

    try std.testing.expectEqual(types.kResultOk, iface.vtable.registerEventHandler(iface, first.asInterface(), 1));
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.registerEventHandler(iface, second.asInterface(), 2));
    try std.testing.expectEqual(@as(types.uint32, 1), second.ref_count.load(.monotonic));
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.unregisterEventHandler(iface, second.asInterface()));
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.unregisterEventHandler(iface, null));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.unregisterEventHandler(iface, first.asInterface()));
}

test "linux run loop registers and triggers timer handlers" {
    const Loop = RunLoop(1, 1);
    const Handler = TimerHandler(struct {});
    var loop = Loop{};
    var handler = Handler{};
    const iface = loop.asInterface();
    const timer_handler = handler.asInterface();

    try std.testing.expectEqual(types.kResultOk, iface.vtable.registerTimer(iface, timer_handler, 16));
    try std.testing.expectEqual(@as(types.uint32, 2), handler.ref_count.load(.monotonic));
    try std.testing.expectEqual(types.kResultOk, loop.triggerTimer(timer_handler));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.timer_count);
    try std.testing.expectEqual(types.kResultOk, iface.vtable.unregisterTimer(iface, timer_handler));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.ref_count.load(.monotonic));
}

test "linux run loop updates duplicate timers and rejects full storage" {
    const Loop = RunLoop(1, 1);
    const Handler = TimerHandler(struct {});
    var loop = Loop{};
    var first = Handler{};
    var second = Handler{};
    const iface = loop.asInterface();

    try std.testing.expectEqual(types.kResultOk, iface.vtable.registerTimer(iface, first.asInterface(), 16));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.registerTimer(iface, first.asInterface(), 32));
    try std.testing.expectEqual(@as(types.uint32, 2), first.ref_count.load(.monotonic));
    try std.testing.expectEqual(@as(Linux.TimerInterval, 32), loop.timer_handlers[0].interval);
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.registerTimer(iface, null, 16));
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.registerTimer(iface, second.asInterface(), 64));
    try std.testing.expectEqual(@as(types.uint32, 1), second.ref_count.load(.monotonic));
    try std.testing.expectEqual(types.kResultFalse, loop.triggerTimer(second.asInterface()));
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.unregisterTimer(iface, second.asInterface()));
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.unregisterTimer(iface, null));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.unregisterTimer(iface, first.asInterface()));
    try std.testing.expectEqual(@as(types.uint32, 1), first.ref_count.load(.monotonic));
}

test "linux run loop supports query interface" {
    const Loop = RunLoop(1, 1);
    var loop = Loop{};
    const iface = loop.asInterface();

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &iplugview.irun_loop_iid, &queried));
    try std.testing.expect(queried != null);
    const queried_loop: *Linux.IRunLoop = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_loop.vtable.release(queried_loop));
}
