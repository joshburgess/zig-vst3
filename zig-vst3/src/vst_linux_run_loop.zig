const builtin = @import("builtin");
const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const iplugview = @import("pluginterfaces/gui/iplugview.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");

const Linux = iplugview.Linux;

pub const PollDescriptor = struct {
    fd: Linux.FileDescriptor,
    ready: bool = false,
};

pub const PumpReport = struct {
    ready_events: usize = 0,
    fired_timers: usize = 0,
    waited_milliseconds: u32 = 0,
};

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

        const owner = interface_map.ownerFromField(Self, Linux.IEventHandler, "iface");

        fn query(ptr: *anyopaque, requested_iid: [*c]const tuid.TUID, out: [*c]?*anyopaque) callconv(.c) types.tresult {
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

        const owner = interface_map.ownerFromField(Self, Linux.ITimerHandler, "iface");

        fn query(ptr: *anyopaque, requested_iid: [*c]const tuid.TUID, out: [*c]?*anyopaque) callconv(.c) types.tresult {
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

            fn set(self: *EventEntry, handler: *Linux.IEventHandler, fd: Linux.FileDescriptor) void {
                self.handler = handler;
                self.fd = fd;
                _ = handler.vtable.addRef(handler);
            }

            fn clear(self: *EventEntry) void {
                if (self.handler) |handler| _ = handler.vtable.release(handler);
                self.* = .{};
            }
        };

        const TimerEntry = extern struct {
            handler: ?*Linux.ITimerHandler = null,
            interval: Linux.TimerInterval = 0,
            deadline_milliseconds: u64 = 0,

            fn set(
                self: *TimerEntry,
                handler: *Linux.ITimerHandler,
                interval: Linux.TimerInterval,
                now_milliseconds: u64,
            ) void {
                self.handler = handler;
                self.interval = interval;
                self.deadline_milliseconds =
                    now_milliseconds +| interval;
                _ = handler.vtable.addRef(handler);
            }

            fn clear(self: *TimerEntry) void {
                if (self.handler) |handler| _ = handler.vtable.release(handler);
                self.* = .{};
            }
        };

        iface: Linux.IRunLoop = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        event_handlers: [max_event_handlers]EventEntry = [_]EventEntry{.{}} ** max_event_handlers,
        timer_handlers: [max_timer_handlers]TimerEntry = [_]TimerEntry{.{}} ** max_timer_handlers,
        clock_milliseconds: u64 = 0,

        pub fn asInterface(self: *Self) *Linux.IRunLoop {
            return &self.iface;
        }

        pub fn triggerEvent(self: *Self, fd: Linux.FileDescriptor) types.tresult {
            const entry = self.findEventEntryByFd(fd) orelse return types.kResultFalse;
            const handler = entry.handler orelse return types.kResultFalse;
            handler.vtable.onFDIsSet(handler, fd);
            return types.kResultOk;
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

        pub fn pollDescriptors(
            self: *const Self,
            output: []PollDescriptor,
        ) !usize {
            var count: usize = 0;
            for (&self.event_handlers) |*entry| {
                if (entry.handler == null) continue;
                if (entry.fd < 0)
                    return error.InvalidRunLoopEventHandler;
                if (count == output.len)
                    return error.PollDescriptorCapacityExceeded;
                output[count] = .{ .fd = entry.fd };
                count += 1;
            }
            return count;
        }

        pub fn nextTimeoutMilliseconds(
            self: *const Self,
            now_milliseconds: u64,
            maximum_wait_milliseconds: u32,
        ) !u32 {
            if (now_milliseconds < self.clock_milliseconds)
                return error.RunLoopClockMovedBackwards;
            var timeout: u64 = maximum_wait_milliseconds;
            for (&self.timer_handlers) |*entry| {
                if (entry.handler == null) continue;
                if (entry.interval == 0)
                    return error.InvalidRunLoopTimer;
                const remaining = if (entry.deadline_milliseconds <= now_milliseconds)
                    0
                else
                    entry.deadline_milliseconds - now_milliseconds;
                timeout = @min(timeout, remaining);
            }
            return @intCast(timeout);
        }

        pub fn dispatch(
            self: *Self,
            now_milliseconds: u64,
            descriptors: []const PollDescriptor,
        ) !PumpReport {
            if (now_milliseconds < self.clock_milliseconds)
                return error.RunLoopClockMovedBackwards;
            self.clock_milliseconds = now_milliseconds;

            var report = PumpReport{};
            for (descriptors) |descriptor| {
                if (!descriptor.ready) continue;
                if (self.triggerEvent(descriptor.fd) == types.kResultOk)
                    report.ready_events += 1;
            }
            for (&self.timer_handlers) |*entry| {
                const handler = entry.handler orelse continue;
                if (entry.interval == 0)
                    return error.InvalidRunLoopTimer;
                if (entry.deadline_milliseconds > now_milliseconds)
                    continue;
                const elapsed =
                    now_milliseconds - entry.deadline_milliseconds;
                const periods = elapsed / entry.interval + 1;
                const advance = std.math.mul(
                    u64,
                    periods,
                    entry.interval,
                ) catch std.math.maxInt(u64);
                entry.deadline_milliseconds = std.math.add(
                    u64,
                    entry.deadline_milliseconds,
                    advance,
                ) catch std.math.maxInt(u64);
                handler.vtable.onTimer(handler);
                report.fired_timers += 1;
            }
            return report;
        }

        /// Call only after the client has stopped registering callbacks
        pub fn deinit(self: *Self) void {
            for (&self.event_handlers) |*entry| entry.clear();
            for (&self.timer_handlers) |*entry| entry.clear();
        }

        const owner = interface_map.ownerFromField(Self, Linux.IRunLoop, "iface");

        fn findEventEntry(self: *Self, handler: *Linux.IEventHandler) ?*EventEntry {
            for (&self.event_handlers) |*entry| {
                if (entry.handler == handler) return entry;
            }
            return null;
        }

        pub fn findEventEntryByFd(self: *Self, fd: Linux.FileDescriptor) ?*EventEntry {
            for (&self.event_handlers) |*entry| {
                if (entry.handler != null and entry.fd == fd) return entry;
            }
            return null;
        }

        fn appendEventEntry(self: *Self, handler: *Linux.IEventHandler, fd: Linux.FileDescriptor) ?*EventEntry {
            for (&self.event_handlers) |*entry| {
                if (entry.handler == null) {
                    entry.set(handler, fd);
                    return entry;
                }
            }
            return null;
        }

        fn findTimerEntry(self: *Self, handler: *Linux.ITimerHandler) ?*TimerEntry {
            for (&self.timer_handlers) |*entry| {
                if (entry.handler == handler) return entry;
            }
            return null;
        }

        fn appendTimerEntry(self: *Self, handler: *Linux.ITimerHandler, interval: Linux.TimerInterval) ?*TimerEntry {
            for (&self.timer_handlers) |*entry| {
                if (entry.handler == null) {
                    entry.set(
                        handler,
                        interval,
                        self.clock_milliseconds,
                    );
                    return entry;
                }
            }
            return null;
        }

        fn query(ptr: *anyopaque, requested_iid: [*c]const tuid.TUID, out: [*c]?*anyopaque) callconv(.c) types.tresult {
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
            if (self.findEventEntry(event_handler)) |entry| {
                entry.fd = fd;
                return types.kResultOk;
            }
            _ = self.appendEventEntry(event_handler, fd) orelse return types.kResultFalse;
            return types.kResultOk;
        }

        fn unregisterEventHandler(ptr: *anyopaque, handler: ?*Linux.IEventHandler) callconv(.c) types.tresult {
            const event_handler = handler orelse return types.kInvalidArgument;
            const entry = owner(ptr).findEventEntry(event_handler) orelse return types.kResultFalse;
            entry.clear();
            return types.kResultOk;
        }

        fn registerTimer(ptr: *anyopaque, handler: ?*Linux.ITimerHandler, interval: Linux.TimerInterval) callconv(.c) types.tresult {
            const timer_handler = handler orelse return types.kInvalidArgument;
            if (interval == 0) return types.kInvalidArgument;
            const self = owner(ptr);
            if (self.findTimerEntry(timer_handler)) |entry| {
                entry.interval = interval;
                entry.deadline_milliseconds =
                    self.clock_milliseconds +| interval;
                return types.kResultOk;
            }
            _ = self.appendTimerEntry(timer_handler, interval) orelse return types.kResultFalse;
            return types.kResultOk;
        }

        fn unregisterTimer(ptr: *anyopaque, handler: ?*Linux.ITimerHandler) callconv(.c) types.tresult {
            const timer_handler = handler orelse return types.kInvalidArgument;
            const entry = owner(ptr).findTimerEntry(timer_handler) orelse return types.kResultFalse;
            entry.clear();
            return types.kResultOk;
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

pub fn Driver(
    comptime max_event_handlers: usize,
    comptime max_timer_handlers: usize,
    comptime Api: type,
) type {
    return struct {
        const Self = @This();
        const Loop = RunLoop(
            max_event_handlers,
            max_timer_handlers,
        );

        run_loop: Loop,
        api: Api,
        poll_storage: [max_event_handlers]PollDescriptor =
            undefined,

        pub fn init(api: Api) Self {
            var result = Self{
                .run_loop = .{},
                .api = api,
            };
            result.run_loop.clock_milliseconds =
                result.api.nowMilliseconds();
            return result;
        }

        pub fn asInterface(self: *Self) *Linux.IRunLoop {
            return self.run_loop.asInterface();
        }

        pub fn pump(
            self: *Self,
            maximum_wait_milliseconds: u32,
        ) !PumpReport {
            const before = self.api.nowMilliseconds();
            if (before < self.run_loop.clock_milliseconds)
                return error.RunLoopClockMovedBackwards;
            self.run_loop.clock_milliseconds = before;
            const descriptor_count =
                try self.run_loop.pollDescriptors(
                    &self.poll_storage,
                );
            const timeout =
                try self.run_loop.nextTimeoutMilliseconds(
                    before,
                    maximum_wait_milliseconds,
                );
            for (self.poll_storage[0..descriptor_count]) |*descriptor|
                descriptor.ready = false;
            try self.api.poll(
                self.poll_storage[0..descriptor_count],
                timeout,
            );
            const after = self.api.nowMilliseconds();
            var report = try self.run_loop.dispatch(
                after,
                self.poll_storage[0..descriptor_count],
            );
            report.waited_milliseconds = if (after - before >
                std.math.maxInt(u32))
                std.math.maxInt(u32)
            else
                @intCast(after - before);
            return report;
        }

        pub fn deinit(self: *Self) void {
            self.run_loop.deinit();
        }
    };
}

const maximum_system_poll_descriptors = 64;

const LinuxPollApi = struct {
    io: std.Io,

    fn nowMilliseconds(self: *@This()) u64 {
        const nanoseconds =
            std.Io.Clock.awake.now(self.io).nanoseconds;
        if (nanoseconds <= 0) return 0;
        const milliseconds = @divFloor(
            nanoseconds,
            std.time.ns_per_ms,
        );
        if (milliseconds > std.math.maxInt(u64))
            return std.math.maxInt(u64);
        return @intCast(milliseconds);
    }

    fn poll(
        _: *@This(),
        descriptors: []PollDescriptor,
        timeout_milliseconds: u32,
    ) !void {
        if (descriptors.len > maximum_system_poll_descriptors)
            return error.TooManyRunLoopPollDescriptors;
        var poll_fds: [maximum_system_poll_descriptors]std.posix.pollfd =
            undefined;
        for (descriptors, 0..) |descriptor, index| {
            poll_fds[index] = .{
                .fd = descriptor.fd,
                .events = std.posix.POLL.IN,
                .revents = 0,
            };
        }
        _ = try std.posix.poll(
            poll_fds[0..descriptors.len],
            @intCast(@min(
                timeout_milliseconds,
                std.math.maxInt(i32),
            )),
        );
        for (descriptors, 0..) |*descriptor, index| {
            descriptor.ready =
                poll_fds[index].revents != 0;
        }
    }
};

const UnsupportedPollApi = struct {
    io: std.Io,

    fn nowMilliseconds(_: *@This()) u64 {
        return 0;
    }

    fn poll(
        _: *@This(),
        _: []PollDescriptor,
        _: u32,
    ) !void {
        return error.UnsupportedPlatform;
    }
};

pub const SystemPollApi = if (builtin.os.tag == .linux)
    LinuxPollApi
else
    UnsupportedPollApi;

pub fn StandaloneDriver(
    comptime max_event_handlers: usize,
    comptime max_timer_handlers: usize,
) type {
    return Driver(
        max_event_handlers,
        max_timer_handlers,
        SystemPollApi,
    );
}

pub fn initStandaloneDriver(
    comptime max_event_handlers: usize,
    comptime max_timer_handlers: usize,
    io: std.Io,
) StandaloneDriver(max_event_handlers, max_timer_handlers) {
    return .init(.{ .io = io });
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
    try std.testing.expect(loop.findEventEntryByFd(7) != null);
    try std.testing.expectEqual(@as(?*Loop.EventEntry, null), loop.findEventEntryByFd(8));
    try std.testing.expectEqual(types.kResultOk, loop.triggerEvent(7));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.event_count);
    try std.testing.expectEqual(@as(Linux.FileDescriptor, 7), handler.last_fd);
    try std.testing.expectEqual(types.kResultOk, iface.vtable.unregisterEventHandler(iface, event_handler));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.ref_count.load(.monotonic));
    try std.testing.expectEqual(@as(?*Linux.IEventHandler, null), loop.event_handlers[0].handler);
    try std.testing.expectEqual(@as(Linux.FileDescriptor, -1), loop.event_handlers[0].fd);
    try std.testing.expectEqual(types.kResultFalse, loop.triggerEvent(7));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.event_count);
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
    try std.testing.expectEqual(@as(types.uint32, 1), timer.timer_count);

    var event_query: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, event.asInterface().vtable.queryInterface(event.asInterface(), &iplugview.ievent_handler_iid, &event_query));
    try std.testing.expect(event_query != null);
    const queried_event: *Linux.IEventHandler = @ptrCast(@alignCast(event_query.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_event.vtable.release(queried_event));

    event_query = null;
    try std.testing.expectEqual(types.kResultOk, event.asInterface().vtable.queryInterface(event.asInterface(), &funknown.iid, &event_query));
    try std.testing.expectEqual(@as(?*anyopaque, event.asInterface()), event_query);
    try std.testing.expectEqual(@as(types.uint32, 2), event.ref_count.load(.seq_cst));
    const queried_event_unknown: *Linux.IEventHandler = @ptrCast(@alignCast(event_query.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_event_unknown.vtable.release(queried_event_unknown));

    var timer_query: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, timer.asInterface().vtable.queryInterface(timer.asInterface(), &iplugview.itimer_handler_iid, &timer_query));
    try std.testing.expect(timer_query != null);
    const queried_timer: *Linux.ITimerHandler = @ptrCast(@alignCast(timer_query.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_timer.vtable.release(queried_timer));

    timer_query = null;
    try std.testing.expectEqual(types.kResultOk, timer.asInterface().vtable.queryInterface(timer.asInterface(), &funknown.iid, &timer_query));
    try std.testing.expectEqual(@as(?*anyopaque, timer.asInterface()), timer_query);
    try std.testing.expectEqual(@as(types.uint32, 2), timer.ref_count.load(.seq_cst));
    const queried_timer_unknown: *Linux.ITimerHandler = @ptrCast(@alignCast(timer_query.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_timer_unknown.vtable.release(queried_timer_unknown));
}

test "linux event and timer handlers clear unsupported query output" {
    const Event = EventHandler(struct {});
    const Timer = TimerHandler(struct {});
    var event = Event{};
    var timer = Timer{};

    var queried: ?*anyopaque = @ptrFromInt(0x1000);
    try std.testing.expectEqual(types.kNoInterface, event.asInterface().vtable.queryInterface(event.asInterface(), &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);

    queried = @ptrFromInt(0x1000);
    try std.testing.expectEqual(types.kNoInterface, timer.asInterface().vtable.queryInterface(timer.asInterface(), &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
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
    try std.testing.expectEqual(types.kResultFalse, loop.triggerTimer(timer_handler));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.timer_count);
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
    try std.testing.expectEqual(@as(u64, 32), loop.timer_handlers[0].deadline_milliseconds);
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.registerTimer(iface, null, 16));
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.registerTimer(iface, second.asInterface(), 0));
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.registerTimer(iface, second.asInterface(), 64));
    try std.testing.expectEqual(@as(types.uint32, 1), second.ref_count.load(.monotonic));
    try std.testing.expectEqual(types.kResultFalse, loop.triggerTimer(second.asInterface()));
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.unregisterTimer(iface, second.asInterface()));
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.unregisterTimer(iface, null));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.unregisterTimer(iface, first.asInterface()));
    try std.testing.expectEqual(@as(types.uint32, 1), first.ref_count.load(.monotonic));
    try std.testing.expectEqual(@as(?*Linux.ITimerHandler, null), loop.timer_handlers[0].handler);
    try std.testing.expectEqual(@as(Linux.TimerInterval, 0), loop.timer_handlers[0].interval);
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

    queried = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &funknown.iid, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, iface), queried);
    try std.testing.expectEqual(@as(types.uint32, 2), loop.ref_count.load(.seq_cst));
    const queried_unknown: *Linux.IRunLoop = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_unknown.vtable.release(queried_unknown));
}

test "linux run loop clears unsupported query output" {
    const Loop = RunLoop(1, 1);
    var loop = Loop{};
    const iface = loop.asInterface();

    var queried: ?*anyopaque = @ptrFromInt(0x1000);
    try std.testing.expectEqual(types.kNoInterface, iface.vtable.queryInterface(iface, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
}

test "linux run loop driver dispatches descriptors and periodic timers" {
    const MockApi = struct {
        now_milliseconds: u64,
        elapsed_milliseconds: u32 = 0,
        ready_fd: ?Linux.FileDescriptor = null,
        last_timeout_milliseconds: u32 = 0,

        fn nowMilliseconds(self: *@This()) u64 {
            return self.now_milliseconds;
        }

        fn poll(
            self: *@This(),
            descriptors: []PollDescriptor,
            timeout_milliseconds: u32,
        ) !void {
            self.last_timeout_milliseconds =
                timeout_milliseconds;
            const elapsed = @min(
                self.elapsed_milliseconds,
                timeout_milliseconds,
            );
            self.now_milliseconds += elapsed;
            if (self.ready_fd) |ready_fd| {
                for (descriptors) |*descriptor| {
                    if (descriptor.fd == ready_fd)
                        descriptor.ready = true;
                }
            }
        }
    };
    const LoopDriver = Driver(2, 2, MockApi);
    const Event = EventHandler(struct {});
    const Timer = TimerHandler(struct {});

    var driver = LoopDriver.init(.{
        .now_milliseconds = 100,
    });
    var event = Event{};
    var timer = Timer{};
    const iface = driver.asInterface();
    try std.testing.expectEqual(
        types.kResultOk,
        iface.vtable.registerEventHandler(
            iface,
            event.asInterface(),
            7,
        ),
    );
    try std.testing.expectEqual(
        types.kResultOk,
        iface.vtable.registerTimer(
            iface,
            timer.asInterface(),
            10,
        ),
    );

    driver.api.elapsed_milliseconds = 10;
    driver.api.ready_fd = 7;
    const first = try driver.pump(100);
    try std.testing.expectEqual(@as(usize, 1), first.ready_events);
    try std.testing.expectEqual(@as(usize, 1), first.fired_timers);
    try std.testing.expectEqual(@as(u32, 10), first.waited_milliseconds);
    try std.testing.expectEqual(
        @as(u32, 10),
        driver.api.last_timeout_milliseconds,
    );
    try std.testing.expectEqual(@as(types.uint32, 1), event.event_count);
    try std.testing.expectEqual(@as(types.uint32, 1), timer.timer_count);

    driver.api.elapsed_milliseconds = 5;
    driver.api.ready_fd = null;
    const second = try driver.pump(100);
    try std.testing.expectEqual(@as(usize, 0), second.ready_events);
    try std.testing.expectEqual(@as(usize, 0), second.fired_timers);
    try std.testing.expectEqual(@as(u32, 5), second.waited_milliseconds);

    const third = try driver.run_loop.dispatch(145, &.{});
    try std.testing.expectEqual(@as(usize, 1), third.fired_timers);
    try std.testing.expectEqual(
        @as(u64, 150),
        driver.run_loop.timer_handlers[0].deadline_milliseconds,
    );
    try std.testing.expectError(
        error.RunLoopClockMovedBackwards,
        driver.run_loop.dispatch(144, &.{}),
    );

    driver.deinit();
    try std.testing.expectEqual(
        @as(types.uint32, 1),
        event.ref_count.load(.monotonic),
    );
    try std.testing.expectEqual(
        @as(types.uint32, 1),
        timer.ref_count.load(.monotonic),
    );
}

test "linux run loop driver contains malformed retained entries" {
    const Loop = RunLoop(1, 1);
    const Event = EventHandler(struct {});
    const Timer = TimerHandler(struct {});
    var loop = Loop{};
    var event = Event{};
    var timer = Timer{};

    loop.event_handlers[0].handler = event.asInterface();
    loop.event_handlers[0].fd = -1;
    var descriptors: [1]PollDescriptor = undefined;
    try std.testing.expectError(
        error.InvalidRunLoopEventHandler,
        loop.pollDescriptors(&descriptors),
    );
    loop.event_handlers[0] = .{};

    loop.timer_handlers[0].handler = timer.asInterface();
    loop.timer_handlers[0].interval = 0;
    try std.testing.expectError(
        error.InvalidRunLoopTimer,
        loop.nextTimeoutMilliseconds(0, 100),
    );
    try std.testing.expectError(
        error.InvalidRunLoopTimer,
        loop.dispatch(0, &.{}),
    );
    loop.timer_handlers[0] = .{};
}

test "system standalone run loop exposes the Steinberg interface" {
    var driver = initStandaloneDriver(2, 2, std.testing.io);
    defer driver.deinit();
    try std.testing.expectEqual(
        &driver.run_loop.iface,
        driver.asInterface(),
    );
    if (builtin.os.tag != .linux) {
        try std.testing.expectError(
            error.UnsupportedPlatform,
            driver.pump(0),
        );
    }
}
