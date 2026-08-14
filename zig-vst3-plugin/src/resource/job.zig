const std = @import("std");
const realtime_audit = @import("../realtime_audit.zig");

pub const Status = enum {
    idle,
    queued,
    validating,
    loading,
    ready,
    cancelled,
    failed,
};

pub const WorkerPhase = enum {
    validating,
    loading,
};

pub const FrameworkFailure = enum {
    none,
    worker_unavailable,
    work_limit,
    result_limit,
    deadline,
};

pub const ProgressError = error{
    InvalidTotalUnits,
    InvalidProgress,
    JobSuperseded,
};

pub fn Outcome(comptime Result: type, comptime Failure: type) type {
    return union(enum) {
        success: struct {
            value: Result,
            result_units: usize,
        },
        failure: Failure,
        cancelled,
    };
}

pub const WorkerContext = struct {
    generation: u64,
    maximum_work_units: usize,
    latest_generation: *const std.atomic.Value(u64),
    cancelled_generation: *const std.atomic.Value(u64),
    shutting_down: *const std.atomic.Value(bool),
    progress_owner: *anyopaque,
    update_progress: *const fn (*anyopaque, u64, usize, usize) bool,
    update_phase: *const fn (*anyopaque, u64, WorkerPhase) bool,
    io: std.Io,
    deadline_nanoseconds: ?i96,
    work_limit_exceeded: bool = false,
    deadline_exceeded: bool = false,

    pub fn cancellationRequested(self: *WorkerContext) bool {
        if (self.shutting_down.load(.acquire) or
            self.latest_generation.load(.acquire) != self.generation or
            self.cancelled_generation.load(.acquire) == self.generation)
        {
            return true;
        }
        if (self.deadline_nanoseconds) |deadline| {
            if (std.Io.Clock.awake.now(self.io).nanoseconds >= deadline) {
                self.deadline_exceeded = true;
                return true;
            }
        }
        return false;
    }

    pub fn setTotalUnits(self: *WorkerContext, total_units: usize) ProgressError!void {
        if (total_units == 0 or total_units > self.maximum_work_units) {
            self.work_limit_exceeded = true;
            return error.InvalidTotalUnits;
        }
        if (!self.update_progress(self.progress_owner, self.generation, 0, total_units)) {
            return error.JobSuperseded;
        }
    }

    pub fn setPhase(self: *WorkerContext, phase: WorkerPhase) ProgressError!void {
        if (!self.update_phase(self.progress_owner, self.generation, phase)) return error.JobSuperseded;
    }

    pub fn advance(self: *WorkerContext, completed_units: usize, total_units: usize) ProgressError!void {
        if (total_units == 0 or total_units > self.maximum_work_units) {
            self.work_limit_exceeded = true;
            return error.InvalidTotalUnits;
        }
        if (!self.update_progress(self.progress_owner, self.generation, completed_units, total_units)) {
            return error.InvalidProgress;
        }
    }
};

pub fn Job(comptime Config: type) type {
    const Request = Config.Request;
    const Result = Config.Result;
    const Failure = Config.Failure;
    const WorkOutcome = Outcome(Result, Failure);
    const maximum_work_units: usize = Config.maximum_work_units;
    const maximum_result_units: usize = Config.maximum_result_units;
    const maximum_runtime_nanoseconds: i64 = if (@hasDecl(Config, "maximum_runtime_nanoseconds"))
        Config.maximum_runtime_nanoseconds
    else
        0;

    if (maximum_work_units == 0) @compileError("resource job work limit must be positive");
    if (maximum_result_units == 0) @compileError("resource job result limit must be positive");
    if (maximum_runtime_nanoseconds < 0) @compileError("resource job runtime limit cannot be negative");

    return struct {
        const Self = @This();

        pub const Snapshot = struct {
            status: Status,
            generation: u64,
            completed_units: usize,
            total_units: usize,
            framework_failure: FrameworkFailure,
            failure: ?Failure,
            cancellation_pending: bool,
            result_available: bool,

            pub fn progress(self: Snapshot) f64 {
                if (!self.valid()) return 0.0;
                if (self.total_units == 0) return 0.0;
                return @as(f64, @floatFromInt(self.completed_units)) /
                    @as(f64, @floatFromInt(self.total_units));
            }

            pub fn canCancel(self: Snapshot) bool {
                return self.valid() and !self.cancellation_pending and
                    (self.status == .queued or self.status == .validating or self.status == .loading);
            }

            pub fn canRetry(self: Snapshot) bool {
                return self.valid() and (self.status == .cancelled or self.status == .failed);
            }

            pub fn valid(self: Snapshot) bool {
                if ((self.generation == 0 and self.status != .idle) or
                    self.total_units > maximum_work_units or
                    (self.total_units == 0 and self.completed_units != 0) or
                    self.completed_units > self.total_units)
                {
                    return false;
                }
                const active = self.status == .queued or
                    self.status == .validating or self.status == .loading;
                if (self.cancellation_pending and !active) return false;
                if (self.framework_failure != .none and self.failure != null)
                    return false;
                return switch (self.status) {
                    .idle => self.completed_units == 0 and
                        self.total_units == 0 and
                        self.framework_failure == .none and
                        self.failure == null and
                        !self.cancellation_pending and
                        !self.result_available,
                    .queued => self.completed_units == 0 and
                        self.total_units == 0 and
                        self.framework_failure == .none and
                        self.failure == null and
                        !self.result_available,
                    .validating, .loading => self.framework_failure == .none and
                        self.failure == null and
                        !self.result_available,
                    .ready => self.completed_units == self.total_units and
                        self.framework_failure == .none and
                        self.failure == null and
                        !self.cancellation_pending,
                    .cancelled => self.framework_failure == .none and
                        self.failure == null and
                        !self.cancellation_pending and
                        !self.result_available,
                    .failed => (self.framework_failure != .none or
                        self.failure != null) and
                        !self.cancellation_pending and
                        !self.result_available,
                };
            }
        };

        const WorkItem = struct {
            generation: u64,
            request: Request,
        };

        mutex: std.Io.Mutex = .init,
        thread: ?std.Thread = null,
        worker_running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        running_generation: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        latest_generation: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        cancelled_generation: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        shutting_down: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        queued: ?WorkItem = null,
        last_request: ?Request = null,
        status: Status = .idle,
        generation: u64 = 0,
        completed_units: usize = 0,
        total_units: usize = 0,
        framework_failure: FrameworkFailure = .none,
        failure: ?Failure = null,
        result: ?Result = null,
        result_generation: u64 = 0,

        pub fn init() Self {
            return .{};
        }

        pub fn deinit(self: *Self) void {
            self.lock();
            self.shutting_down.store(true, .release);
            self.generation = self.nextGeneration();
            self.latest_generation.store(self.generation, .release);
            self.cancelled_generation.store(0, .release);
            self.queued = null;
            const abandoned = self.result;
            self.result = null;
            self.unlock();
            self.joinWorker();
            if (abandoned) |value| dispose(value);
        }

        pub fn submit(self: *Self, request: Request) bool {
            if (!realtime_audit.observe(.allocation)) return false;
            self.reapWorker();
            self.lock();
            if (self.shutting_down.load(.acquire)) {
                self.unlock();
                return false;
            }
            const generation = self.nextGeneration();
            const abandoned = self.result;
            self.result = null;
            self.result_generation = 0;
            self.generation = generation;
            self.latest_generation.store(generation, .release);
            self.cancelled_generation.store(0, .release);
            self.last_request = request;
            self.queued = .{ .generation = generation, .request = request };
            self.status = .queued;
            self.completed_units = 0;
            self.total_units = 0;
            self.framework_failure = .none;
            self.failure = null;

            if (!self.worker_running.load(.acquire)) {
                self.worker_running.store(true, .release);
                self.thread = std.Thread.spawn(.{}, run, .{self}) catch {
                    self.worker_running.store(false, .release);
                    self.queued = null;
                    self.status = .failed;
                    self.framework_failure = .worker_unavailable;
                    self.unlock();
                    if (abandoned) |value| dispose(value);
                    return false;
                };
            }
            self.unlock();
            if (abandoned) |value| dispose(value);
            return true;
        }

        pub fn retry(self: *Self) bool {
            if (!realtime_audit.observe(.lock)) return false;
            self.lock();
            const retryable = self.status == .failed or self.status == .cancelled;
            const request = if (retryable) self.last_request else null;
            self.unlock();
            return if (request) |value| self.submit(value) else false;
        }

        pub fn requestCancel(self: *Self) bool {
            if (!realtime_audit.observe(.lock)) return false;
            self.lock();
            defer self.unlock();
            if (self.status != .queued and self.status != .validating and self.status != .loading) return false;
            self.cancelled_generation.store(self.generation, .release);
            return true;
        }

        pub fn reset(self: *Self) void {
            if (!realtime_audit.observe(.lock)) return;
            self.lock();
            const abandoned = self.result;
            self.result = null;
            self.result_generation = 0;
            self.generation = self.nextGeneration();
            self.latest_generation.store(self.generation, .release);
            self.cancelled_generation.store(0, .release);
            self.queued = null;
            self.last_request = null;
            self.status = .idle;
            self.completed_units = 0;
            self.total_units = 0;
            self.framework_failure = .none;
            self.failure = null;
            self.unlock();
            if (abandoned) |value| dispose(value);
            self.joinWorker();
        }

        pub fn snapshot(self: *const Self) Snapshot {
            if (!realtime_audit.observe(.lock)) return emptySnapshot();
            const mutable: *Self = @constCast(self);
            mutable.lock();
            defer mutable.unlock();
            return .{
                .status = self.status,
                .generation = self.generation,
                .completed_units = self.completed_units,
                .total_units = self.total_units,
                .framework_failure = self.framework_failure,
                .failure = self.failure,
                .cancellation_pending = self.generation != 0 and
                    self.cancelled_generation.load(.acquire) == self.generation,
                .result_available = self.result != null,
            };
        }

        pub fn takeResult(self: *Self, generation: u64) ?Result {
            if (!realtime_audit.observe(.lock)) return null;
            self.lock();
            defer self.unlock();
            if (self.status != .ready or self.result_generation != generation) return null;
            const value = self.result;
            self.result = null;
            return value;
        }

        pub fn wait(self: *Self) void {
            if (!realtime_audit.observe(.lock)) return;
            self.joinWorker();
        }

        fn run(self: *Self) void {
            const io = std.Io.Threaded.global_single_threaded.io();
            while (true) {
                self.lock();
                const work = self.queued orelse {
                    self.worker_running.store(false, .release);
                    self.unlock();
                    return;
                };
                self.queued = null;
                self.running_generation.store(work.generation, .release);
                if (work.generation == self.generation) self.status = .validating;
                self.unlock();

                const started = std.Io.Clock.awake.now(io).nanoseconds;
                var context = WorkerContext{
                    .generation = work.generation,
                    .maximum_work_units = maximum_work_units,
                    .latest_generation = &self.latest_generation,
                    .cancelled_generation = &self.cancelled_generation,
                    .shutting_down = &self.shutting_down,
                    .progress_owner = self,
                    .update_progress = updateProgress,
                    .update_phase = updatePhase,
                    .io = io,
                    .deadline_nanoseconds = if (maximum_runtime_nanoseconds == 0)
                        null
                    else
                        started + maximum_runtime_nanoseconds,
                };
                const outcome: WorkOutcome = if (context.cancellationRequested())
                    .cancelled
                else
                    Config.run(work.request, &context);
                _ = context.cancellationRequested();

                var discarded: ?Result = null;
                self.lock();
                if (work.generation != self.generation) {
                    discarded = successValue(outcome);
                } else if (context.deadline_exceeded) {
                    discarded = successValue(outcome);
                    self.finishFrameworkFailure(.deadline);
                } else if (context.work_limit_exceeded) {
                    discarded = successValue(outcome);
                    self.finishFrameworkFailure(.work_limit);
                } else if (self.cancelled_generation.load(.acquire) == work.generation) {
                    discarded = successValue(outcome);
                    self.status = .cancelled;
                } else switch (outcome) {
                    .success => |success| {
                        if (success.result_units > maximum_result_units) {
                            discarded = success.value;
                            self.finishFrameworkFailure(.result_limit);
                        } else {
                            self.result = success.value;
                            self.result_generation = work.generation;
                            self.status = .ready;
                            self.completed_units = self.total_units;
                        }
                    },
                    .failure => |failure| {
                        self.failure = failure;
                        self.status = .failed;
                    },
                    .cancelled => self.status = .cancelled,
                }
                if (work.generation == self.generation) {
                    self.cancelled_generation.store(0, .release);
                }
                const continue_running = self.queued != null and !self.shutting_down.load(.acquire);
                _ = self.running_generation.cmpxchgStrong(
                    work.generation,
                    0,
                    .acq_rel,
                    .acquire,
                );
                if (!continue_running) self.worker_running.store(false, .release);
                self.unlock();
                if (discarded) |value| dispose(value);
                if (!continue_running) return;
            }
        }

        fn updateProgress(owner: *anyopaque, generation: u64, completed_units: usize, total_units: usize) bool {
            const self: *Self = @ptrCast(@alignCast(owner));
            self.lock();
            defer self.unlock();
            if (generation != self.generation or total_units == 0 or total_units > maximum_work_units or
                completed_units < self.completed_units or completed_units > total_units or
                (self.total_units != 0 and self.total_units != total_units))
            {
                return false;
            }
            self.completed_units = completed_units;
            self.total_units = total_units;
            return true;
        }

        fn updatePhase(owner: *anyopaque, generation: u64, phase: WorkerPhase) bool {
            const self: *Self = @ptrCast(@alignCast(owner));
            self.lock();
            defer self.unlock();
            if (generation != self.generation) return false;
            self.status = switch (phase) {
                .validating => .validating,
                .loading => .loading,
            };
            return true;
        }

        fn finishFrameworkFailure(self: *Self, failure: FrameworkFailure) void {
            self.framework_failure = failure;
            self.failure = null;
            self.status = .failed;
        }

        fn nextGeneration(self: *const Self) u64 {
            const latest = self.latest_generation.load(.acquire);
            const running = self.running_generation.load(.acquire);
            var candidate = self.generation;
            while (true) {
                candidate +%= 1;
                if (candidate == 0) candidate = 1;
                if (candidate == latest or candidate == running) continue;
                if (self.queued) |queued| {
                    if (candidate == queued.generation) continue;
                }
                return candidate;
            }
        }

        fn successValue(outcome: WorkOutcome) ?Result {
            return switch (outcome) {
                .success => |success| success.value,
                else => null,
            };
        }

        fn emptySnapshot() Snapshot {
            return .{
                .status = .idle,
                .generation = 0,
                .completed_units = 0,
                .total_units = 0,
                .framework_failure = .none,
                .failure = null,
                .cancellation_pending = false,
                .result_available = false,
            };
        }

        fn dispose(value: Result) void {
            if (comptime @hasDecl(Config, "dispose")) Config.dispose(value);
        }

        fn reapWorker(self: *Self) void {
            if (self.worker_running.load(.acquire)) return;
            self.joinWorker();
        }

        fn joinWorker(self: *Self) void {
            if (self.thread) |thread| {
                thread.join();
                self.thread = null;
            }
        }

        fn lock(self: *Self) void {
            _ = realtime_audit.observe(.lock);
            self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        }

        fn unlock(self: *Self) void {
            self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());
        }
    };
}

test "resource job loads a bounded non-audio fixture" {
    const Path = @import("path.zig").BoundedPath(1024);
    const Source = enum { drop, picker, restored_state };
    const FixtureRequest = struct {
        path: Path,
        source: Source,
    };
    const FixtureResult = struct { value: u32, source: Source };
    const FixtureJob = Job(struct {
        pub const Request = FixtureRequest;
        pub const Result = FixtureResult;
        pub const Failure = enum { open_failed, malformed };
        pub const maximum_work_units = 32;
        pub const maximum_result_units = 1;

        pub fn run(request: Request, context: *WorkerContext) Outcome(Result, Failure) {
            const file = std.Io.Dir.cwd().openFile(context.io, request.path.slice(), .{}) catch return .{ .failure = .open_failed };
            defer file.close(context.io);
            var bytes: [32]u8 = undefined;
            const count = file.readPositionalAll(context.io, &bytes, 0) catch return .{ .failure = .malformed };
            context.setPhase(.loading) catch return .cancelled;
            context.setTotalUnits(count) catch return .cancelled;
            context.advance(count, count) catch return .cancelled;
            const value = std.fmt.parseInt(u32, std.mem.trim(u8, bytes[0..count], " \n\r\t"), 10) catch return .{ .failure = .malformed };
            return .{ .success = .{ .value = .{ .value = value, .source = request.source }, .result_units = 1 } };
        }
    });

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "model.fixture", .data = "42\n" });
    var path_bytes: [1024]u8 = undefined;
    const path_length = try temporary.dir.realPathFile(std.testing.io, "model.fixture", &path_bytes);

    var resource_job = FixtureJob.init();
    defer resource_job.deinit();
    const path = try Path.init(path_bytes[0..path_length]);
    for ([_]Source{ .drop, .picker, .restored_state }) |source| {
        try std.testing.expect(resource_job.submit(.{ .path = path, .source = source }));
        resource_job.wait();
        const snapshot = resource_job.snapshot();
        try std.testing.expectEqual(Status.ready, snapshot.status);
        try std.testing.expectEqual(@as(usize, 3), snapshot.completed_units);
        const result = resource_job.takeResult(snapshot.generation).?;
        try std.testing.expectEqual(@as(u32, 42), result.value);
        try std.testing.expectEqual(source, result.source);
    }
}

test "resource job replaces work and rejects stale completion" {
    const disposed = struct {
        var count = std.atomic.Value(u32).init(0);
    };
    const synchronization = struct {
        var first_started = std.atomic.Value(bool).init(false);
        var release_first = std.atomic.Value(bool).init(false);
    };
    const ReplacementJob = Job(struct {
        pub const Request = struct { value: u32 };
        pub const Result = *u32;
        pub const Failure = enum { unavailable };
        pub const maximum_work_units = 1;
        pub const maximum_result_units = 1;

        pub fn run(request: Request, context: *WorkerContext) Outcome(Result, Failure) {
            context.setTotalUnits(1) catch return .cancelled;
            if (request.value == 1) {
                synchronization.first_started.store(true, .release);
                while (!synchronization.release_first.load(.acquire)) std.Thread.yield() catch {};
            }
            const result = std.heap.page_allocator.create(u32) catch return .{ .failure = .unavailable };
            result.* = request.value;
            return .{ .success = .{ .value = result, .result_units = 1 } };
        }

        pub fn dispose(result: Result) void {
            std.heap.page_allocator.destroy(result);
            _ = disposed.count.fetchAdd(1, .acq_rel);
        }
    });

    var resource_job = ReplacementJob.init();
    defer resource_job.deinit();
    disposed.count.store(0, .release);
    synchronization.first_started.store(false, .release);
    synchronization.release_first.store(false, .release);
    try std.testing.expect(resource_job.submit(.{ .value = 1 }));
    while (!synchronization.first_started.load(.acquire)) std.Thread.yield() catch {};
    try std.testing.expect(resource_job.submit(.{ .value = 2 }));
    synchronization.release_first.store(true, .release);
    resource_job.wait();
    const snapshot = resource_job.snapshot();
    try std.testing.expectEqual(Status.ready, snapshot.status);
    try std.testing.expectEqual(@as(u32, 1), disposed.count.load(.acquire));
    const result = resource_job.takeResult(snapshot.generation).?;
    defer ReplacementJob.dispose(result);
    try std.testing.expectEqual(@as(u32, 2), result.*);
}

test "resource job cancellation and teardown stop cooperative workers" {
    const synchronization = struct {
        var started = std.atomic.Value(bool).init(false);
        var stopped = std.atomic.Value(u32).init(0);
    };
    const CooperativeJob = Job(struct {
        pub const Request = u8;
        pub const Result = u8;
        pub const Failure = enum { unused };
        pub const maximum_work_units = 1;
        pub const maximum_result_units = 1;

        pub fn run(_: Request, context: *WorkerContext) Outcome(Result, Failure) {
            context.setTotalUnits(1) catch return .cancelled;
            synchronization.started.store(true, .release);
            while (!context.cancellationRequested()) std.Thread.yield() catch {};
            _ = synchronization.stopped.fetchAdd(1, .acq_rel);
            return .cancelled;
        }
    });

    synchronization.started.store(false, .release);
    synchronization.stopped.store(0, .release);
    var cancelled_job = CooperativeJob.init();
    try std.testing.expect(cancelled_job.submit(1));
    while (!synchronization.started.load(.acquire)) std.Thread.yield() catch {};
    try std.testing.expect(cancelled_job.requestCancel());
    cancelled_job.wait();
    const cancelled_snapshot = cancelled_job.snapshot();
    try std.testing.expectEqual(Status.cancelled, cancelled_snapshot.status);
    try std.testing.expect(!cancelled_snapshot.cancellation_pending);
    try std.testing.expect(cancelled_snapshot.valid());
    cancelled_job.deinit();

    synchronization.started.store(false, .release);
    var teardown_job = CooperativeJob.init();
    try std.testing.expect(teardown_job.submit(2));
    while (!synchronization.started.load(.acquire)) std.Thread.yield() catch {};
    teardown_job.deinit();
    try std.testing.expectEqual(@as(u32, 2), synchronization.stopped.load(.acquire));

    synchronization.started.store(false, .release);
    var reset_job = CooperativeJob.init();
    defer reset_job.deinit();
    try std.testing.expect(reset_job.submit(3));
    while (!synchronization.started.load(.acquire)) std.Thread.yield() catch {};
    reset_job.reset();
    try std.testing.expectEqual(Status.idle, reset_job.snapshot().status);
    try std.testing.expectEqual(@as(u32, 3), synchronization.stopped.load(.acquire));
}

test "resource job enforces a cooperative runtime deadline" {
    const DeadlineJob = Job(struct {
        pub const Request = void;
        pub const Result = u8;
        pub const Failure = enum { unused };
        pub const maximum_work_units = 1;
        pub const maximum_result_units = 1;
        pub const maximum_runtime_nanoseconds = 1;

        pub fn run(_: Request, context: *WorkerContext) Outcome(Result, Failure) {
            while (!context.cancellationRequested()) std.Thread.yield() catch {};
            return .cancelled;
        }
    });

    var resource_job = DeadlineJob.init();
    defer resource_job.deinit();
    try std.testing.expect(resource_job.submit({}));
    resource_job.wait();
    try std.testing.expectEqual(FrameworkFailure.deadline, resource_job.snapshot().framework_failure);
}

test "resource job enforces work and result limits" {
    const LimitedJob = Job(struct {
        pub const Request = enum { work, result };
        pub const Result = u8;
        pub const Failure = enum { unused };
        pub const maximum_work_units = 4;
        pub const maximum_result_units = 2;

        pub fn run(request: Request, context: *WorkerContext) Outcome(Result, Failure) {
            if (request == .work) {
                context.setTotalUnits(5) catch {};
                return .cancelled;
            }
            return .{ .success = .{ .value = 7, .result_units = 3 } };
        }
    });

    var resource_job = LimitedJob.init();
    defer resource_job.deinit();
    try std.testing.expect(resource_job.submit(.work));
    resource_job.wait();
    try std.testing.expectEqual(FrameworkFailure.work_limit, resource_job.snapshot().framework_failure);
    try std.testing.expect(resource_job.retry());
    try std.testing.expect(resource_job.submit(.result));
    resource_job.wait();
    try std.testing.expectEqual(FrameworkFailure.result_limit, resource_job.snapshot().framework_failure);
    resource_job.reset();
    const reset_snapshot = resource_job.snapshot();
    try std.testing.expectEqual(Status.idle, reset_snapshot.status);
    try std.testing.expect(!reset_snapshot.cancellation_pending);
}

test "resource job snapshots contain malformed presentation state" {
    const SnapshotJob = Job(struct {
        pub const Request = void;
        pub const Result = void;
        pub const Failure = enum { unavailable };
        pub const maximum_work_units = 4;
        pub const maximum_result_units = 1;

        pub fn run(_: Request, _: *WorkerContext) Outcome(Result, Failure) {
            return .{ .success = .{ .value = {}, .result_units = 1 } };
        }
    });

    const valid = SnapshotJob.Snapshot{
        .status = .loading,
        .generation = 1,
        .completed_units = 2,
        .total_units = 4,
        .framework_failure = .none,
        .failure = null,
        .cancellation_pending = false,
        .result_available = false,
    };
    try std.testing.expect(valid.valid());
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), valid.progress(), 0.0001);
    try std.testing.expect(valid.canCancel());

    var malformed = valid;
    malformed.completed_units = 8;
    try std.testing.expect(!malformed.valid());
    try std.testing.expectEqual(@as(f64, 0.0), malformed.progress());
    try std.testing.expect(!malformed.canCancel());
    try std.testing.expect(!malformed.canRetry());
    malformed = valid;
    malformed.cancellation_pending = true;
    try std.testing.expect(!malformed.canCancel());
    try std.testing.expect(malformed.valid());
    malformed.status = .ready;
    try std.testing.expect(!malformed.valid());

    malformed = valid;
    malformed.generation = 0;
    try std.testing.expect(!malformed.valid());
    malformed = valid;
    malformed.total_units = 5;
    try std.testing.expect(!malformed.valid());
    malformed = valid;
    malformed.status = .failed;
    try std.testing.expect(!malformed.valid());

    const idle = SnapshotJob.Snapshot{
        .status = .idle,
        .generation = 0,
        .completed_units = 0,
        .total_units = 0,
        .framework_failure = .none,
        .failure = null,
        .cancellation_pending = false,
        .result_available = false,
    };
    try std.testing.expect(idle.valid());

    var initial_job = SnapshotJob.init();
    defer initial_job.deinit();
    const initial = initial_job.snapshot();
    try std.testing.expect(initial.valid());
    try std.testing.expect(!initial.cancellation_pending);
}

test "resource job generation skips retained active identities" {
    const GenerationJob = Job(struct {
        pub const Request = u8;
        pub const Result = void;
        pub const Failure = enum { unused };
        pub const maximum_work_units = 1;
        pub const maximum_result_units = 1;

        pub fn run(_: Request, _: *WorkerContext) Outcome(Result, Failure) {
            return .{ .success = .{ .value = {}, .result_units = 1 } };
        }
    });

    var resource_job = GenerationJob.init();
    defer resource_job.deinit();
    resource_job.generation = std.math.maxInt(u64);
    resource_job.running_generation.store(1, .release);
    resource_job.latest_generation.store(2, .release);
    resource_job.queued = .{ .generation = 2, .request = 7 };
    resource_job.worker_running.store(true, .release);

    try std.testing.expect(resource_job.submit(8));
    try std.testing.expectEqual(@as(u64, 3), resource_job.generation);
    try std.testing.expectEqual(
        @as(u64, 3),
        resource_job.latest_generation.load(.acquire),
    );
    try std.testing.expectEqual(@as(u64, 3), resource_job.queued.?.generation);
}

test "resource job control operations reject realtime use before locking" {
    const ControlJob = Job(struct {
        pub const Request = u8;
        pub const Result = u8;
        pub const Failure = enum { unused };
        pub const maximum_work_units = 1;
        pub const maximum_result_units = 1;

        pub fn run(request: Request, _: *WorkerContext) Outcome(Result, Failure) {
            return .{ .success = .{ .value = request, .result_units = 1 } };
        }
    });

    var resource_job = ControlJob.init();
    defer resource_job.deinit();

    const scope = realtime_audit.Scope.enter();
    try std.testing.expect(!resource_job.retry());
    try std.testing.expect(!resource_job.requestCancel());
    resource_job.reset();
    const snapshot = resource_job.snapshot();
    try std.testing.expect(snapshot.valid());
    try std.testing.expectEqual(Status.idle, snapshot.status);
    try std.testing.expect(resource_job.takeResult(1) == null);
    resource_job.wait();
    try std.testing.expect(!resource_job.submit(1));
    const report = scope.leave();

    try std.testing.expectEqual(realtime_audit.Operation.lock, report.first_violation.?);
    try std.testing.expectEqual(@as(u32, 6), report.count(.lock));
    try std.testing.expectEqual(@as(u32, 1), report.count(.allocation));
    try std.testing.expectEqual(@as(u64, 0), resource_job.generation);
    try std.testing.expectEqual(Status.idle, resource_job.status);
}
