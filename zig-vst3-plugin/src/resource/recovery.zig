const std = @import("std");
const exchange_mod = @import("exchange.zig");
const gui_progress = @import("../gui_progress.zig");
const job_mod = @import("job.zig");
const reference_mod = @import("reference.zig");

pub const RequestKind = enum {
    import,
    restored_state,
    relink,
};

pub fn Prepared(comptime Resource: type, comptime metadata_capacity: usize) type {
    return struct {
        resource: *Resource,
        identity: reference_mod.Identity,
        resource_schema_version: u32,
        metadata: reference_mod.BoundedMetadata(metadata_capacity),
    };
}

pub fn Recovery(comptime Config: type) type {
    const ResourceType = Config.Resource;
    const path_capacity: usize = Config.path_capacity;
    const metadata_capacity: usize = Config.metadata_capacity;
    const FailureType = Config.Failure;
    const allow_mutable_active: bool = if (@hasDecl(Config, "mutable_active")) Config.mutable_active else false;
    const has_preparation_context = @hasDecl(Config, "PreparationContext");
    const PreparationContext = if (has_preparation_context) Config.PreparationContext else void;
    const has_publication_metadata = @hasDecl(Config, "PublicationMetadata");
    const PublicationMetadata = if (has_publication_metadata) Config.PublicationMetadata else void;
    const has_publication_ready = @hasDecl(Config, "publicationReady");
    const Path = @import("path.zig").BoundedPath(path_capacity);
    const Reference = reference_mod.Reference(path_capacity, metadata_capacity);
    const ReferenceState = reference_mod.State(path_capacity, metadata_capacity);
    const PreparedResource = Prepared(ResourceType, metadata_capacity);

    if (!@hasDecl(Config, "prepare")) @compileError("resource recovery requires Config.prepare");
    if (!@hasDecl(Config, "destroy")) @compileError("resource recovery requires Config.destroy");
    if (!@hasDecl(Config, "failureStatus")) @compileError("resource recovery requires Config.failureStatus");
    if (Config.slot_capacity < 2) @compileError("resource recovery requires at least two exchange slots");
    if (has_preparation_context and !@hasDecl(Config, "initial_preparation_context")) {
        @compileError("resource recovery preparation contexts require Config.initial_preparation_context");
    }
    if (has_publication_metadata and !@hasDecl(Config, "publicationMetadata")) {
        @compileError("resource recovery publication metadata requires Config.publicationMetadata");
    }
    if (has_publication_ready and (!has_preparation_context or !has_publication_metadata)) {
        @compileError("resource recovery publicationReady requires preparation context and publication metadata");
    }

    const Exchange = exchange_mod.Exchange(struct {
        pub const Resource = ResourceType;
        pub const slot_capacity = Config.slot_capacity;
        pub const mutable_active = allow_mutable_active;

        pub fn destroy(resource: *ResourceType) void {
            Config.destroy(resource);
        }
    });

    const SnapshotType = struct {
        status: reference_mod.RecoveryStatus,
        resolution: reference_mod.RecoveryStatus,
        generation: u64,
        reference: ReferenceState,
        failure: ?FailureType,
        publication_metadata: ?PublicationMetadata,

        pub fn validate(self: *const @This()) !void {
            try self.reference.validate();
            if (self.status != .empty and self.generation == 0) {
                return error.InvalidRecoveryGeneration;
            }
            if (self.status == .empty and
                (self.reference != .empty or
                    self.resolution != .empty or
                    self.failure != null or
                    self.publication_metadata != null))
            {
                return error.InvalidRecoveryState;
            }
            if (self.status == .ready) {
                if (self.reference != .linked or
                    (self.resolution != .ready and self.resolution != .moved) or
                    self.failure != null or
                    self.publication_metadata == null)
                {
                    return error.InvalidRecoveryState;
                }
            } else if (self.publication_metadata != null) {
                return error.InvalidRecoveryState;
            }
            if (self.status != .ready and self.resolution != self.status) {
                return error.InvalidRecoveryState;
            }
            if (self.failure) |failure| {
                if (self.status != Config.failureStatus(failure)) {
                    return error.InvalidRecoveryFailure;
                }
            } else if (self.status == .missing or self.status == .moved) {
                return error.InvalidRecoveryFailure;
            }
        }

        pub fn valid(self: *const @This()) bool {
            self.validate() catch return false;
            return true;
        }
    };

    const Completion = struct {
        const CompletionSelf = @This();
        const Publication = enum { published, changed, unsupported, stale, busy };

        mutex: std.Io.Mutex = .init,
        reference: ReferenceState = .empty,
        status: reference_mod.RecoveryStatus = .empty,
        resolution: reference_mod.RecoveryStatus = .empty,
        failure: ?FailureType = null,
        publication_metadata: ?PublicationMetadata = null,
        latest_generation: u64 = 0,

        fn begin(self: *CompletionSelf, generation: u64, desired: ?ReferenceState) void {
            self.lock();
            defer self.unlock();
            if (desired) |state| self.reference = state;
            self.latest_generation = generation;
            self.status = .restoring;
            self.resolution = .restoring;
            self.failure = null;
            self.publication_metadata = null;
        }

        fn empty(self: *CompletionSelf, generation: u64) void {
            self.lock();
            defer self.unlock();
            self.reference = .empty;
            self.latest_generation = generation;
            self.status = .empty;
            self.resolution = .empty;
            self.failure = null;
            self.publication_metadata = null;
        }

        fn finishFailure(self: *CompletionSelf, generation: u64, failure: ?FailureType) void {
            self.lock();
            defer self.unlock();
            if (generation != self.latest_generation) return;
            self.failure = failure;
            self.publication_metadata = null;
            self.status = if (failure) |value| Config.failureStatus(value) else .failed;
            self.resolution = self.status;
        }

        fn publish(
            self: *CompletionSelf,
            generation: u64,
            request_path: Path,
            expected: ?Reference,
            prepared: PreparedResource,
            publication_metadata: PublicationMetadata,
            exchange: *Exchange,
        ) Publication {
            self.lock();
            defer self.unlock();
            if (generation != self.latest_generation) return .stale;
            const resolution = if (expected) |stored| blk: {
                if (stored.resource_schema_version != prepared.resource_schema_version) {
                    break :blk reference_mod.RecoveryStatus.unsupported;
                }
                break :blk stored.classifyCandidate(request_path.slice(), prepared.identity);
            } else reference_mod.RecoveryStatus.ready;
            if (resolution == .changed) {
                self.status = .changed;
                self.resolution = .changed;
                self.failure = null;
                return .changed;
            }
            if (resolution == .unsupported) {
                self.status = .unsupported;
                self.resolution = .unsupported;
                self.failure = null;
                return .unsupported;
            }
            exchange.publish(generation, prepared.resource) catch {
                self.status = .failed;
                self.resolution = .failed;
                self.failure = null;
                return .busy;
            };
            self.reference = .{ .linked = .{
                .path = request_path,
                .identity = prepared.identity,
                .resource_schema_version = prepared.resource_schema_version,
                .metadata = prepared.metadata,
            } };
            self.status = .ready;
            self.resolution = resolution;
            self.failure = null;
            self.publication_metadata = publication_metadata;
            return .published;
        }

        fn snapshot(self: *const CompletionSelf) SnapshotType {
            const mutable: *CompletionSelf = @constCast(self);
            mutable.lock();
            defer mutable.unlock();
            return .{
                .status = self.status,
                .resolution = self.resolution,
                .generation = self.latest_generation,
                .reference = self.reference,
                .failure = self.failure,
                .publication_metadata = self.publication_metadata,
            };
        }

        fn lock(self: *CompletionSelf) void {
            self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        }

        fn unlock(self: *CompletionSelf) void {
            self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());
        }
    };

    const RequestType = struct {
        path: Path,
        expected_reference: ?Reference,
        kind: RequestKind,
        publication_generation: u64,
        running_publication_generation: *std.atomic.Value(u64),
        exchange: *Exchange,
        completion: *Completion,
        preparation_context: PreparationContext,
    };

    const SourceRequest = struct {
        path: Path,
        expected_reference: ?Reference,
        kind: RequestKind,
        desired: ?ReferenceState,
    };

    const PreparationJob = job_mod.Job(struct {
        pub const Request = RequestType;
        pub const Result = u64;
        pub const Failure = Config.Failure;
        pub const maximum_work_units = Config.maximum_work_units;
        pub const maximum_result_units = Config.maximum_result_units;
        pub const maximum_runtime_nanoseconds = if (@hasDecl(Config, "maximum_runtime_nanoseconds"))
            Config.maximum_runtime_nanoseconds
        else
            0;

        pub fn run(request: Request, context: *job_mod.WorkerContext) job_mod.Outcome(Result, Failure) {
            request.running_publication_generation.store(
                request.publication_generation,
                .release,
            );
            defer {
                _ = request.running_publication_generation.cmpxchgStrong(
                    request.publication_generation,
                    0,
                    .acq_rel,
                    .acquire,
                );
            }
            const outcome = if (has_preparation_context)
                Config.prepare(request.path, request.preparation_context, context)
            else
                Config.prepare(request.path, context);
            return switch (outcome) {
                .success => |success| complete(request, context, success.value, success.result_units),
                .failure => |failure| failureOutcome(request, failure),
                .cancelled => cancelledOutcome(request),
            };
        }

        fn complete(
            request: Request,
            context: *job_mod.WorkerContext,
            prepared: PreparedResource,
            result_units: usize,
        ) job_mod.Outcome(Result, Failure) {
            if (context.cancellationRequested()) {
                Config.destroy(prepared.resource);
                return cancelledOutcome(request);
            }
            if (result_units == 0 or result_units > Config.maximum_result_units) {
                Config.destroy(prepared.resource);
                request.completion.finishFailure(request.publication_generation, null);
                return .{ .success = .{ .value = request.publication_generation, .result_units = result_units } };
            }
            const publication_metadata: PublicationMetadata = if (has_publication_metadata)
                Config.publicationMetadata(prepared.resource)
            else {};
            const publication = request.completion.publish(
                request.publication_generation,
                request.path,
                request.expected_reference,
                prepared,
                publication_metadata,
                request.exchange,
            );
            if (publication != .published) Config.destroy(prepared.resource);
            return .{ .success = .{ .value = request.publication_generation, .result_units = result_units } };
        }

        fn failureOutcome(request: Request, failure: Failure) job_mod.Outcome(Result, Failure) {
            request.completion.finishFailure(request.publication_generation, failure);
            return .{ .failure = failure };
        }

        fn cancelledOutcome(request: Request) job_mod.Outcome(Result, Failure) {
            request.completion.finishFailure(request.publication_generation, null);
            return .cancelled;
        }
    });

    return struct {
        const Self = @This();

        pub const component_state_maximum_encoded_size = ReferenceState.maximum_encoded_size;

        pub const Snapshot = SnapshotType;
        pub const ProgressSnapshot = PreparationJob.Snapshot;
        pub const PresentationSnapshot = struct {
            status: reference_mod.RecoveryStatus,
            resolution: reference_mod.RecoveryStatus,
            generation: u64,
            reference: ReferenceState,
            progress: gui_progress.Snapshot,
            can_cancel: bool,
            can_retry: bool,
            cancellation_pending: bool,

            pub fn statusText(self: PresentationSnapshot) []const u8 {
                if (!self.valid()) return "";
                return @tagName(self.status);
            }

            pub fn metadata(self: *const PresentationSnapshot) []const u8 {
                if (!self.valid()) return "";
                return switch (self.reference) {
                    .empty => "",
                    .linked => |*linked| linked.metadata.slice(),
                };
            }

            pub fn validate(self: *const PresentationSnapshot) !void {
                try self.reference.validate();
                try self.progress.validate();
                if (self.progress.generation != self.generation) return error.InvalidPresentationGeneration;
                const expected_progress: gui_progress.State = switch (self.status) {
                    .restoring => .running,
                    .ready => .complete,
                    .missing, .changed, .unsupported, .failed => .failed,
                    .empty, .moved => .idle,
                };
                if (self.progress.state != expected_progress) return error.InvalidPresentationProgress;
                if (self.can_cancel and (self.status != .restoring or self.cancellation_pending)) {
                    return error.InvalidPresentationActions;
                }
                if (self.cancellation_pending and self.status != .restoring) {
                    return error.InvalidPresentationActions;
                }
                if (self.can_retry and self.progress.state != .failed) {
                    return error.InvalidPresentationActions;
                }
            }

            pub fn valid(self: *const PresentationSnapshot) bool {
                self.validate() catch return false;
                return true;
            }
        };

        preparation: PreparationJob = .init(),
        exchange: Exchange = .{},
        completion: Completion = .{},
        clear_before_generation: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        running_publication_generation: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        next_publication_generation: u64 = 0,
        observed_job_generation: u64 = 0,
        latest_source_request: ?SourceRequest = null,
        preparation_context: PreparationContext = if (has_preparation_context)
            Config.initial_preparation_context
        else {},

        pub fn init() Self {
            return .{};
        }

        pub fn deinit(self: *Self) void {
            self.preparation.deinit();
            self.exchange.retireAllAfterProcessingStops();
            self.exchange.deinit();
        }

        pub fn importPath(self: *Self, path: []const u8) bool {
            const owned_path = Path.init(path) catch return false;
            return self.submit(owned_path, null, .import, null);
        }

        pub fn restore(self: *Self, state: ReferenceState) void {
            switch (state) {
                .empty => {
                    _ = self.preparation.requestCancel();
                    self.latest_source_request = null;
                    const generation = self.nextGeneration();
                    self.completion.empty(generation);
                    self.clear_before_generation.store(generation, .release);
                },
                .linked => |linked| {
                    const generation = self.nextGeneration();
                    self.clear_before_generation.store(generation, .release);
                    _ = self.submitGeneration(generation, linked.path, linked, .restored_state, state);
                },
            }
        }

        pub fn relink(self: *Self, path: []const u8) bool {
            const current = self.completion.snapshot().reference;
            const linked = switch (current) {
                .empty => return false,
                .linked => |value| value,
            };
            const owned_path = Path.init(path) catch return false;
            return self.submit(owned_path, linked, .relink, null);
        }

        pub fn requestCancel(self: *Self) bool {
            return self.preparation.requestCancel();
        }

        pub fn retry(self: *Self) bool {
            const job_snapshot = self.preparation.snapshot();
            if (job_snapshot.status != .failed and job_snapshot.status != .cancelled) return false;
            const generation = self.completion.snapshot().generation;
            self.completion.begin(generation, null);
            if (self.preparation.retry()) return true;
            self.completion.finishFailure(generation, null);
            return false;
        }

        pub fn updatePreparationContext(self: *Self, context: PreparationContext) bool {
            if (!has_preparation_context) {
                @compileError("updatePreparationContext requires Config.PreparationContext");
            }
            self.preparation_context = context;
            const source = self.latest_source_request orelse return true;
            return self.submit(source.path, source.expected_reference, source.kind, source.desired);
        }

        /// Collects worker completion on the calling control thread.
        /// `Config.publicationReady`, when present, runs synchronously here.
        pub fn poll(self: *Self) void {
            const job_snapshot = self.preparation.snapshot();
            if (job_snapshot.generation == 0 or job_snapshot.generation == self.observed_job_generation) return;
            if (job_snapshot.status == .ready) {
                _ = self.preparation.takeResult(job_snapshot.generation);
                if (has_publication_ready) {
                    const completion = self.completion.snapshot();
                    if (completion.status == .ready and
                        completion.generation == job_snapshot.generation)
                    {
                        Config.publicationReady(
                            self.preparation_context,
                            completion.generation,
                            completion.publication_metadata.?,
                        );
                    }
                }
            }
            if (job_snapshot.status == .ready or job_snapshot.status == .failed or job_snapshot.status == .cancelled) {
                self.observed_job_generation = job_snapshot.generation;
            }
        }

        /// Joins the worker and collects completion on the calling control thread.
        pub fn waitAndPoll(self: *Self) void {
            self.preparation.wait();
            self.poll();
        }

        pub fn snapshot(self: *const Self) Snapshot {
            return self.completion.snapshot();
        }

        pub fn progressSnapshot(self: *const Self) ProgressSnapshot {
            return self.preparation.snapshot();
        }

        pub fn presentationSnapshot(self: *const Self) PresentationSnapshot {
            const completion = self.completion.snapshot();
            const job = self.preparation.snapshot();
            const matching_job = job.generation != 0 and job.generation == completion.generation;
            return .{
                .status = completion.status,
                .resolution = completion.resolution,
                .generation = completion.generation,
                .reference = completion.reference,
                .progress = progressForPresentation(completion.status, completion.generation, job, matching_job),
                .can_cancel = matching_job and job.canCancel(),
                .can_retry = matching_job and job.canRetry(),
                .cancellation_pending = matching_job and job.cancellation_pending,
            };
        }

        pub fn adoptPendingAtBlockBoundary(self: *Self) bool {
            const restore_generation = self.clear_before_generation.swap(0, .acq_rel);
            if (restore_generation != 0) {
                const retired = self.exchange.retireActiveAtBlockBoundary();
                return (self.exchange.adoptPendingAtOrAfter(restore_generation) != null) or retired;
            }
            return self.exchange.adoptPending() != null;
        }

        pub fn adoptPendingThroughAtBlockBoundary(self: *Self, maximum_generation: u64) bool {
            const restore_generation = self.clear_before_generation.swap(0, .acq_rel);
            if (restore_generation != 0) {
                const retired = self.exchange.retireActiveAtBlockBoundary();
                return (self.exchange.adoptPendingInRange(restore_generation, maximum_generation) != null) or retired;
            }
            return self.exchange.adoptPendingThrough(maximum_generation) != null;
        }

        pub fn active(self: *const Self) ?*const ResourceType {
            const active_resource = self.exchange.active() orelse return null;
            return active_resource.resource;
        }

        pub fn activeMutable(self: *Self) ?*ResourceType {
            if (!allow_mutable_active) @compileError("mutable recovery resources require Config.mutable_active = true");
            const active_resource = self.exchange.activeMutable() orelse return null;
            return active_resource.resource;
        }

        pub fn retireActiveAtBlockBoundary(self: *Self) bool {
            return self.exchange.retireActiveAtBlockBoundary();
        }

        pub fn reclaim(self: *Self) usize {
            return self.exchange.reclaim();
        }

        pub fn componentStateEncodedSize(self: *const Self) usize {
            var snapshot_value = self.completion.snapshot();
            return snapshot_value.reference.encodedSize();
        }

        pub fn writeComponentState(self: *const Self, writer: anytype) !void {
            var snapshot_value = self.completion.snapshot();
            try snapshot_value.reference.write(writer);
        }

        pub fn readComponentState(self: *Self, reader: anytype) !void {
            const restored = try ReferenceState.read(reader);
            if (reader.seek != reader.end) return error.TrailingResourceStateData;
            self.restore(restored);
        }

        fn submit(self: *Self, path: Path, expected_reference: ?Reference, kind: RequestKind, desired: ?ReferenceState) bool {
            const generation = self.nextGeneration();
            return self.submitGeneration(generation, path, expected_reference, kind, desired);
        }

        fn submitGeneration(self: *Self, generation: u64, path: Path, expected_reference: ?Reference, kind: RequestKind, desired: ?ReferenceState) bool {
            self.latest_source_request = .{
                .path = path,
                .expected_reference = expected_reference,
                .kind = kind,
                .desired = desired,
            };
            self.completion.begin(generation, desired);
            if (!self.preparation.submit(.{
                .path = path,
                .expected_reference = expected_reference,
                .kind = kind,
                .publication_generation = generation,
                .running_publication_generation = &self.running_publication_generation,
                .exchange = &self.exchange,
                .completion = &self.completion,
                .preparation_context = self.preparation_context,
            })) {
                self.completion.finishFailure(generation, null);
                return false;
            }
            return true;
        }

        fn nextGeneration(self: *Self) u64 {
            const running = self.running_publication_generation.load(.acquire);
            const current = self.completion.snapshot().generation;
            const clear_before = self.clear_before_generation.load(.acquire);
            const exchange_latest = self.exchange.latest_generation.load(.acquire);
            const exchange_active = self.exchange.activeGeneration();
            var candidate = self.next_publication_generation;
            while (true) {
                candidate +%= 1;
                if (candidate == 0) candidate = 1;
                if (candidate == running or
                    candidate == current or
                    candidate == clear_before or
                    candidate == exchange_latest or
                    candidate == exchange_active)
                {
                    continue;
                }
                self.next_publication_generation = candidate;
                return candidate;
            }
        }

        fn progressForPresentation(
            status: reference_mod.RecoveryStatus,
            generation: u64,
            job: ProgressSnapshot,
            matching_job: bool,
        ) gui_progress.Snapshot {
            return switch (status) {
                .restoring => if (matching_job and job.total_units != 0)
                    .{
                        .state = .running,
                        .value = job.progress(),
                        .generation = job.generation,
                    }
                else
                    .{
                        .mode = .indeterminate,
                        .state = .running,
                        .generation = generation,
                    },
                .ready => .{ .state = .complete, .value = 1.0, .generation = generation },
                .missing, .changed, .unsupported, .failed => .{ .state = .failed, .generation = generation },
                .empty, .moved => .{ .generation = generation },
            };
        }
    };
}

test "resource recovery presents one bounded generation to the GUI" {
    const TestResource = struct { value: u32 };
    const metadata_limit = 32;
    const TestPrepared = Prepared(TestResource, metadata_limit);
    const synchronization = struct {
        var started = std.atomic.Value(bool).init(false);
        var release = std.atomic.Value(bool).init(false);
    };
    const TestRecovery = Recovery(struct {
        pub const Resource = TestResource;
        pub const Failure = enum { allocation_failed };
        pub const path_capacity = 64;
        pub const metadata_capacity = metadata_limit;
        pub const slot_capacity = 3;
        pub const maximum_work_units = 4;
        pub const maximum_result_units = 1;

        pub fn prepare(_: @import("path.zig").BoundedPath(path_capacity), context: *job_mod.WorkerContext) job_mod.Outcome(TestPrepared, Failure) {
            context.setPhase(.loading) catch return .cancelled;
            context.setTotalUnits(4) catch return .cancelled;
            context.advance(1, 4) catch return .cancelled;
            synchronization.started.store(true, .release);
            while (!synchronization.release.load(.acquire)) std.Thread.yield() catch {};
            if (context.cancellationRequested()) return .cancelled;
            const resource = std.heap.page_allocator.create(Resource) catch return .{ .failure = .allocation_failed };
            resource.* = .{ .value = 42 };
            return .{ .success = .{
                .value = .{
                    .resource = resource,
                    .identity = reference_mod.Identity.fromBytes("presentation fixture"),
                    .resource_schema_version = 1,
                    .metadata = reference_mod.BoundedMetadata(metadata_capacity).init("ready model") catch {
                        std.heap.page_allocator.destroy(resource);
                        return .{ .failure = .allocation_failed };
                    },
                },
                .result_units = 1,
            } };
        }

        pub fn destroy(resource: *Resource) void {
            std.heap.page_allocator.destroy(resource);
        }

        pub fn failureStatus(_: Failure) reference_mod.RecoveryStatus {
            return .failed;
        }
    });

    synchronization.started.store(false, .release);
    synchronization.release.store(false, .release);
    var recovery = TestRecovery.init();
    defer recovery.deinit();
    try std.testing.expect(recovery.importPath("model.fixture"));
    while (!synchronization.started.load(.acquire)) std.Thread.yield() catch {};

    var retained = recovery.snapshot();
    try std.testing.expect(retained.valid());
    var presentation = recovery.presentationSnapshot();
    try std.testing.expect(presentation.valid());
    try std.testing.expectEqual(reference_mod.RecoveryStatus.restoring, presentation.status);
    try std.testing.expectEqual(gui_progress.State.running, presentation.progress.state);
    try std.testing.expectEqual(gui_progress.Mode.determinate, presentation.progress.mode);
    try std.testing.expectEqual(@as(f64, 0.25), presentation.progress.value);
    try std.testing.expectEqual(presentation.generation, presentation.progress.generation);
    try std.testing.expect(presentation.can_cancel);
    try std.testing.expect(!presentation.can_retry);
    try std.testing.expectEqualStrings("restoring", presentation.statusText());
    try std.testing.expectEqualStrings("", presentation.metadata());

    try std.testing.expect(recovery.requestCancel());
    presentation = recovery.presentationSnapshot();
    try std.testing.expect(presentation.valid());
    try std.testing.expect(presentation.cancellation_pending);
    synchronization.release.store(true, .release);
    recovery.waitAndPoll();

    retained = recovery.snapshot();
    try std.testing.expect(retained.valid());
    presentation = recovery.presentationSnapshot();
    try std.testing.expect(presentation.valid());
    try std.testing.expectEqual(reference_mod.RecoveryStatus.failed, presentation.status);
    try std.testing.expectEqual(gui_progress.State.failed, presentation.progress.state);
    try std.testing.expect(!presentation.can_cancel);
    try std.testing.expect(presentation.can_retry);

    synchronization.started.store(false, .release);
    try std.testing.expect(recovery.retry());
    recovery.waitAndPoll();
    retained = recovery.snapshot();
    try std.testing.expect(retained.valid());
    presentation = recovery.presentationSnapshot();
    try std.testing.expect(presentation.valid());
    try std.testing.expectEqual(reference_mod.RecoveryStatus.ready, presentation.status);
    try std.testing.expectEqual(gui_progress.State.complete, presentation.progress.state);
    try std.testing.expectEqual(@as(f64, 1.0), presentation.progress.value);
    try std.testing.expectEqualStrings("ready model", presentation.metadata());
    try presentation.progress.validate();

    var malformed = presentation;
    malformed.progress.generation +%= 1;
    try std.testing.expectError(error.InvalidPresentationGeneration, malformed.validate());
    try std.testing.expectEqualStrings("", malformed.statusText());
    try std.testing.expectEqualStrings("", malformed.metadata());
    malformed = presentation;
    malformed.can_cancel = true;
    try std.testing.expectError(error.InvalidPresentationActions, malformed.validate());
    malformed = presentation;
    malformed.reference.linked.path.length = TestRecovery.component_state_maximum_encoded_size;
    try std.testing.expect(!malformed.valid());
    try std.testing.expectEqualStrings("", malformed.metadata());

    var malformed_retained = retained;
    malformed_retained.generation = 0;
    try std.testing.expectError(error.InvalidRecoveryGeneration, malformed_retained.validate());
    malformed_retained = retained;
    malformed_retained.status = .restoring;
    try std.testing.expectError(error.InvalidRecoveryState, malformed_retained.validate());
    malformed_retained = retained;
    malformed_retained.reference = .empty;
    try std.testing.expectError(error.InvalidRecoveryState, malformed_retained.validate());
}

test "resource recovery publishes and adopts across generation rollover" {
    const TestResource = struct { generation: u64 };
    const metadata_limit = 8;
    const RolloverRecovery = Recovery(struct {
        pub const Resource = TestResource;
        pub const Failure = enum { allocation_failed };
        pub const path_capacity = 32;
        pub const metadata_capacity = metadata_limit;
        pub const slot_capacity = 2;
        pub const maximum_work_units = 1;
        pub const maximum_result_units = 1;

        pub fn prepare(_: @import("path.zig").BoundedPath(path_capacity), _: *job_mod.WorkerContext) job_mod.Outcome(Prepared(Resource, metadata_capacity), Failure) {
            const resource = std.heap.page_allocator.create(Resource) catch {
                return .{ .failure = .allocation_failed };
            };
            resource.* = .{ .generation = 0 };
            return .{ .success = .{
                .value = .{
                    .resource = resource,
                    .identity = reference_mod.Identity.fromBytes("rollover"),
                    .resource_schema_version = 1,
                    .metadata = reference_mod.BoundedMetadata(metadata_capacity).init("rollover") catch {
                        std.heap.page_allocator.destroy(resource);
                        return .{ .failure = .allocation_failed };
                    },
                },
                .result_units = 1,
            } };
        }

        pub fn destroy(resource: *Resource) void {
            std.heap.page_allocator.destroy(resource);
        }

        pub fn failureStatus(_: Failure) reference_mod.RecoveryStatus {
            return .failed;
        }
    });

    var recovery = RolloverRecovery.init();
    defer recovery.deinit();
    recovery.next_publication_generation = std.math.maxInt(u64) - 1;
    recovery.exchange.latest_generation.store(std.math.maxInt(u64) - 1, .release);

    try std.testing.expect(recovery.importPath("before-wrap"));
    recovery.waitAndPoll();
    try std.testing.expectEqual(std.math.maxInt(u64), recovery.snapshot().generation);
    try std.testing.expectEqual(reference_mod.RecoveryStatus.ready, recovery.snapshot().status);
    try std.testing.expect(!recovery.adoptPendingThroughAtBlockBoundary(std.math.maxInt(u64) - 1));
    try std.testing.expect(recovery.adoptPendingThroughAtBlockBoundary(std.math.maxInt(u64)));

    try std.testing.expect(recovery.importPath("after-wrap"));
    recovery.waitAndPoll();
    try std.testing.expectEqual(@as(u64, 1), recovery.snapshot().generation);
    try std.testing.expectEqual(reference_mod.RecoveryStatus.ready, recovery.snapshot().status);
    try std.testing.expect(!recovery.adoptPendingThroughAtBlockBoundary(std.math.maxInt(u64)));
    try std.testing.expect(recovery.adoptPendingThroughAtBlockBoundary(1));
    try std.testing.expectEqual(@as(usize, 1), recovery.reclaim());

    recovery.next_publication_generation = std.math.maxInt(u64);
    recovery.running_publication_generation.store(1, .release);
    recovery.clear_before_generation.store(2, .release);
    try std.testing.expectEqual(@as(u64, 3), recovery.nextGeneration());
}

test "resource recovery restores, detects changes, and relinks moved content" {
    const metadata_limit = 32;
    const TestResource = struct { value: u32 };
    const TestPrepared = Prepared(TestResource, metadata_limit);
    const TestFailure = enum { missing, unsupported, malformed };
    const TestRecovery = Recovery(struct {
        pub const Resource = TestResource;
        pub const Failure = TestFailure;
        pub const path_capacity = 1024;
        pub const metadata_capacity = metadata_limit;
        pub const slot_capacity = 4;
        pub const maximum_work_units = 64;
        pub const maximum_result_units = 1;

        pub fn prepare(path: @import("path.zig").BoundedPath(path_capacity), context: *job_mod.WorkerContext) job_mod.Outcome(TestPrepared, Failure) {
            const file = std.Io.Dir.cwd().openFile(context.io, path.slice(), .{}) catch return .{ .failure = .missing };
            defer file.close(context.io);
            var bytes: [64]u8 = undefined;
            const count = file.readPositionalAll(context.io, &bytes, 0) catch return .{ .failure = .malformed };
            if (count == bytes.len) return .{ .failure = .unsupported };
            context.setTotalUnits(@max(count, 1)) catch return .cancelled;
            context.advance(@max(count, 1), @max(count, 1)) catch return .cancelled;
            const text = std.mem.trim(u8, bytes[0..count], " \r\n\t");
            const value = std.fmt.parseInt(u32, text, 10) catch return .{ .failure = .malformed };
            const resource = std.heap.page_allocator.create(Resource) catch return .{ .failure = .malformed };
            resource.* = .{ .value = value };
            return .{ .success = .{
                .value = .{
                    .resource = resource,
                    .identity = reference_mod.Identity.fromBytes(bytes[0..count]),
                    .resource_schema_version = 1,
                    .metadata = reference_mod.BoundedMetadata(metadata_capacity).init("integer fixture") catch unreachable,
                },
                .result_units = 1,
            } };
        }

        pub fn destroy(resource: *Resource) void {
            std.heap.page_allocator.destroy(resource);
        }

        pub fn failureStatus(failure: Failure) reference_mod.RecoveryStatus {
            return switch (failure) {
                .missing => .missing,
                .unsupported => .unsupported,
                .malformed => .failed,
            };
        }
    });

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "original.fixture", .data = "42\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "moved.fixture", .data = "42\n" });
    var original_path: [1024]u8 = undefined;
    const original_length = try temporary.dir.realPathFile(std.testing.io, "original.fixture", &original_path);
    var moved_path: [1024]u8 = undefined;
    const moved_length = try temporary.dir.realPathFile(std.testing.io, "moved.fixture", &moved_path);

    var recovery = TestRecovery.init();
    defer recovery.deinit();
    try std.testing.expect(recovery.importPath(original_path[0..original_length]));
    recovery.waitAndPoll();
    try std.testing.expectEqual(reference_mod.RecoveryStatus.ready, recovery.snapshot().status);
    try std.testing.expect(recovery.adoptPendingAtBlockBoundary());
    try std.testing.expectEqual(@as(u32, 42), recovery.active().?.value);
    const stored = recovery.snapshot().reference;

    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "original.fixture", .data = "7\n" });
    recovery.restore(stored);
    recovery.waitAndPoll();
    try std.testing.expectEqual(reference_mod.RecoveryStatus.changed, recovery.snapshot().status);
    try std.testing.expectEqualStrings("integer fixture", recovery.snapshot().reference.linked.metadata.slice());
    try std.testing.expectEqual(@as(u32, 42), recovery.active().?.value);

    try std.testing.expect(recovery.relink(moved_path[0..moved_length]));
    recovery.waitAndPoll();
    try std.testing.expectEqual(reference_mod.RecoveryStatus.ready, recovery.snapshot().status);
    try std.testing.expectEqual(reference_mod.RecoveryStatus.moved, recovery.snapshot().resolution);
    try std.testing.expectEqualStrings(moved_path[0..moved_length], recovery.snapshot().reference.linked.path.slice());

    const moved_state = recovery.snapshot().reference;
    try temporary.dir.deleteFile(std.testing.io, "moved.fixture");
    recovery.restore(moved_state);
    recovery.waitAndPoll();
    try std.testing.expectEqual(reference_mod.RecoveryStatus.missing, recovery.snapshot().status);
    try std.testing.expect(recovery.active() != null);
    try std.testing.expect(recovery.adoptPendingAtBlockBoundary());
    try std.testing.expect(recovery.active() == null);
    try std.testing.expectEqual(@as(usize, 2), recovery.reclaim());
}

test "resource recovery streams and publishes a heap-owned model-sized resource" {
    const resource_bytes = 512 * 1024;
    const chunk_bytes = 16 * 1024;
    const metadata_limit = 32;
    const TestResource = struct { bytes: []u8 };
    const TestPrepared = Prepared(TestResource, metadata_limit);
    const TestFailure = enum { missing, invalid, allocation_failed };
    const TestRecovery = Recovery(struct {
        pub const Resource = TestResource;
        pub const Failure = TestFailure;
        pub const path_capacity = 1024;
        pub const metadata_capacity = metadata_limit;
        pub const slot_capacity = 3;
        pub const maximum_work_units = resource_bytes;
        pub const maximum_result_units = resource_bytes;

        pub fn prepare(path: @import("path.zig").BoundedPath(path_capacity), context: *job_mod.WorkerContext) job_mod.Outcome(TestPrepared, Failure) {
            const file = std.Io.Dir.cwd().openFile(context.io, path.slice(), .{}) catch return .{ .failure = .missing };
            defer file.close(context.io);
            const length_u64 = file.length(context.io) catch return .{ .failure = .invalid };
            if (length_u64 == 0 or length_u64 > maximum_work_units) return .{ .failure = .invalid };
            const length: usize = @intCast(length_u64);
            context.setTotalUnits(length) catch return .cancelled;
            context.setPhase(.loading) catch return .cancelled;

            const resource = std.heap.page_allocator.create(Resource) catch return .{ .failure = .allocation_failed };
            resource.bytes = std.heap.page_allocator.alloc(u8, length) catch {
                std.heap.page_allocator.destroy(resource);
                return .{ .failure = .allocation_failed };
            };
            var hasher = reference_mod.IdentityHasher{};
            var offset: usize = 0;
            while (offset < length) {
                if (context.cancellationRequested()) {
                    destroy(resource);
                    return .cancelled;
                }
                const amount = @min(chunk_bytes, length - offset);
                const destination = resource.bytes[offset .. offset + amount];
                const count = file.readPositionalAll(context.io, destination, offset) catch {
                    destroy(resource);
                    return .{ .failure = .invalid };
                };
                if (count != amount) {
                    destroy(resource);
                    return .{ .failure = .invalid };
                }
                hasher.update(destination) catch {
                    destroy(resource);
                    return .{ .failure = .invalid };
                };
                offset += amount;
                context.advance(offset, length) catch {
                    destroy(resource);
                    return .cancelled;
                };
            }
            return .{ .success = .{
                .value = .{
                    .resource = resource,
                    .identity = hasher.final(),
                    .resource_schema_version = 1,
                    .metadata = reference_mod.BoundedMetadata(metadata_capacity).init("generated model fixture") catch unreachable,
                },
                .result_units = length,
            } };
        }

        pub fn destroy(resource: *Resource) void {
            std.heap.page_allocator.free(resource.bytes);
            std.heap.page_allocator.destroy(resource);
        }

        pub fn failureStatus(failure: Failure) reference_mod.RecoveryStatus {
            return switch (failure) {
                .missing => .missing,
                .invalid => .unsupported,
                .allocation_failed => .failed,
            };
        }
    });

    const fixture = try std.testing.allocator.alloc(u8, resource_bytes);
    defer std.testing.allocator.free(fixture);
    for (fixture, 0..) |*byte, index| byte.* = @truncate(index *% 131 +% 17);

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "model.fixture", .data = fixture });
    var path_bytes: [1024]u8 = undefined;
    const path_length = try temporary.dir.realPathFile(std.testing.io, "model.fixture", &path_bytes);

    var recovery = TestRecovery.init();
    defer recovery.deinit();
    try std.testing.expect(recovery.importPath(path_bytes[0..path_length]));
    recovery.waitAndPoll();
    const snapshot = recovery.snapshot();
    try std.testing.expectEqual(reference_mod.RecoveryStatus.ready, snapshot.status);
    try std.testing.expectEqual(@as(u64, resource_bytes), snapshot.reference.linked.identity.byte_length);
    try std.testing.expect(snapshot.reference.linked.identity.eql(reference_mod.Identity.fromBytes(fixture)));
    try std.testing.expect(recovery.adoptPendingAtBlockBoundary());
    const active = recovery.active().?;
    try std.testing.expectEqual(resource_bytes, active.bytes.len);
    try std.testing.expectEqualSlices(u8, fixture[0..64], active.bytes[0..64]);
    try std.testing.expect(recovery.retireActiveAtBlockBoundary());
    try std.testing.expectEqual(@as(usize, 1), recovery.reclaim());
}

test "resource recovery republishes linked content for a new preparation context" {
    const metadata_limit = 16;
    const TestResource = struct { value: u32 };
    const TestPrepared = Prepared(TestResource, metadata_limit);
    const TestFailure = enum { missing, malformed };
    const callbacks = struct {
        var generation = std.atomic.Value(u64).init(0);
        var value = std.atomic.Value(u32).init(0);
    };
    const ContextRecovery = Recovery(struct {
        pub const Resource = TestResource;
        pub const Failure = TestFailure;
        pub const PreparationContext = struct { multiplier: u32 };
        pub const PublicationMetadata = u32;
        pub const initial_preparation_context: PreparationContext = .{ .multiplier = 1 };
        pub const path_capacity = 1024;
        pub const metadata_capacity = metadata_limit;
        pub const slot_capacity = 4;
        pub const maximum_work_units = 32;
        pub const maximum_result_units = 1;

        pub fn prepare(
            path: @import("path.zig").BoundedPath(path_capacity),
            preparation_context: PreparationContext,
            context: *job_mod.WorkerContext,
        ) job_mod.Outcome(TestPrepared, Failure) {
            const file = std.Io.Dir.cwd().openFile(context.io, path.slice(), .{}) catch return .{ .failure = .missing };
            defer file.close(context.io);
            var bytes: [32]u8 = undefined;
            const count = file.readPositionalAll(context.io, &bytes, 0) catch return .{ .failure = .malformed };
            if (count == bytes.len) return .{ .failure = .malformed };
            const value = std.fmt.parseInt(u32, std.mem.trim(u8, bytes[0..count], " \r\n\t"), 10) catch {
                return .{ .failure = .malformed };
            };
            const resource = std.heap.page_allocator.create(Resource) catch return .{ .failure = .malformed };
            resource.* = .{ .value = value * preparation_context.multiplier };
            return .{ .success = .{
                .value = .{
                    .resource = resource,
                    .identity = reference_mod.Identity.fromBytes(bytes[0..count]),
                    .resource_schema_version = 1,
                    .metadata = reference_mod.BoundedMetadata(metadata_capacity).init("context fixture") catch {
                        std.heap.page_allocator.destroy(resource);
                        return .{ .failure = .malformed };
                    },
                },
                .result_units = 1,
            } };
        }

        pub fn destroy(resource: *Resource) void {
            std.heap.page_allocator.destroy(resource);
        }

        pub fn publicationMetadata(resource: *const Resource) PublicationMetadata {
            return resource.value;
        }

        pub fn publicationReady(_: PreparationContext, generation: u64, metadata: PublicationMetadata) void {
            callbacks.value.store(metadata, .release);
            callbacks.generation.store(generation, .release);
        }

        pub fn failureStatus(failure: Failure) reference_mod.RecoveryStatus {
            return switch (failure) {
                .missing => .missing,
                .malformed => .failed,
            };
        }
    });

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "value.fixture", .data = "7\n" });
    var path_bytes: [1024]u8 = undefined;
    const path_length = try temporary.dir.realPathFile(std.testing.io, "value.fixture", &path_bytes);

    callbacks.generation.store(0, .release);
    callbacks.value.store(0, .release);
    var recovery = ContextRecovery.init();
    defer recovery.deinit();
    try std.testing.expect(recovery.importPath(path_bytes[0..path_length]));
    recovery.preparation.wait();
    try std.testing.expectEqual(@as(u64, 0), callbacks.generation.load(.acquire));
    try std.testing.expectEqual(@as(u32, 0), callbacks.value.load(.acquire));
    recovery.poll();
    const first_generation = recovery.snapshot().generation;
    try std.testing.expectEqual(first_generation, callbacks.generation.load(.acquire));
    try std.testing.expectEqual(@as(u32, 7), callbacks.value.load(.acquire));
    try std.testing.expectEqual(@as(?u32, 7), recovery.snapshot().publication_metadata);
    try std.testing.expect(!recovery.adoptPendingThroughAtBlockBoundary(first_generation - 1));
    try std.testing.expect(recovery.active() == null);
    try std.testing.expect(recovery.adoptPendingThroughAtBlockBoundary(first_generation));
    try std.testing.expectEqual(@as(u32, 7), recovery.active().?.value);

    try std.testing.expect(recovery.updatePreparationContext(.{ .multiplier = 3 }));
    recovery.preparation.wait();
    try std.testing.expectEqual(first_generation, callbacks.generation.load(.acquire));
    try std.testing.expectEqual(@as(u32, 7), callbacks.value.load(.acquire));
    recovery.poll();
    const second_generation = recovery.snapshot().generation;
    try std.testing.expectEqual(second_generation, callbacks.generation.load(.acquire));
    try std.testing.expectEqual(@as(u32, 21), callbacks.value.load(.acquire));
    try std.testing.expectEqual(@as(?u32, 21), recovery.snapshot().publication_metadata);
    try std.testing.expectEqual(@as(u32, 7), recovery.active().?.value);
    try std.testing.expect(!recovery.adoptPendingThroughAtBlockBoundary(second_generation - 1));
    try std.testing.expectEqual(@as(u32, 7), recovery.active().?.value);
    try std.testing.expect(recovery.adoptPendingThroughAtBlockBoundary(second_generation));
    try std.testing.expectEqual(@as(u32, 21), recovery.active().?.value);
    try std.testing.expectEqual(@as(usize, 1), recovery.reclaim());
}

test "missing resource state remains recoverable without an editor" {
    const TestResource = struct { value: u8 };
    const metadata_limit = 8;
    const TestFailure = enum { missing };
    const MissingRecovery = Recovery(struct {
        pub const Resource = TestResource;
        pub const Failure = TestFailure;
        pub const path_capacity = 128;
        pub const metadata_capacity = metadata_limit;
        pub const slot_capacity = 2;
        pub const maximum_work_units = 1;
        pub const maximum_result_units = 1;

        pub fn prepare(_: @import("path.zig").BoundedPath(path_capacity), _: *job_mod.WorkerContext) job_mod.Outcome(Prepared(Resource, metadata_capacity), Failure) {
            return .{ .failure = .missing };
        }

        pub fn destroy(resource: *Resource) void {
            std.heap.page_allocator.destroy(resource);
        }

        pub fn failureStatus(_: Failure) reference_mod.RecoveryStatus {
            return .missing;
        }
    });
    const Linked = reference_mod.Reference(128, metadata_limit);
    const state = reference_mod.State(128, metadata_limit){ .linked = try Linked.init(
        "/missing/model.fixture",
        reference_mod.Identity.fromBytes("missing"),
        1,
        "Linear",
    ) };
    var recovery = MissingRecovery.init();
    defer recovery.deinit();
    recovery.restore(state);
    recovery.preparation.wait();
    try std.testing.expectEqual(reference_mod.RecoveryStatus.missing, recovery.snapshot().status);
    try std.testing.expect(recovery.active() == null);
    try std.testing.expectEqualStrings("/missing/model.fixture", recovery.snapshot().reference.linked.path.slice());
}

test "resource recovery rejects an incompatible prepared schema" {
    const TestResource = struct { value: u8 };
    const metadata_limit = 8;
    const TestFailure = enum { failed };
    const SchemaRecovery = Recovery(struct {
        pub const Resource = TestResource;
        pub const Failure = TestFailure;
        pub const path_capacity = 32;
        pub const metadata_capacity = metadata_limit;
        pub const slot_capacity = 2;
        pub const maximum_work_units = 1;
        pub const maximum_result_units = 1;

        pub fn prepare(_: @import("path.zig").BoundedPath(path_capacity), _: *job_mod.WorkerContext) job_mod.Outcome(Prepared(Resource, metadata_capacity), Failure) {
            const resource = std.heap.page_allocator.create(Resource) catch return .{ .failure = .failed };
            resource.* = .{ .value = 2 };
            return .{ .success = .{
                .value = .{
                    .resource = resource,
                    .identity = reference_mod.Identity.fromBytes("fixture"),
                    .resource_schema_version = 2,
                    .metadata = reference_mod.BoundedMetadata(metadata_capacity).init("v2") catch {
                        std.heap.page_allocator.destroy(resource);
                        return .{ .failure = .failed };
                    },
                },
                .result_units = 1,
            } };
        }

        pub fn destroy(resource: *Resource) void {
            std.heap.page_allocator.destroy(resource);
        }

        pub fn failureStatus(_: Failure) reference_mod.RecoveryStatus {
            return .failed;
        }
    });
    const Stored = reference_mod.Reference(32, metadata_limit);
    const state = reference_mod.State(32, metadata_limit){ .linked = try Stored.init(
        "model.fixture",
        reference_mod.Identity.fromBytes("fixture"),
        1,
        "v1",
    ) };
    var recovery = SchemaRecovery.init();
    defer recovery.deinit();
    recovery.restore(state);
    recovery.preparation.wait();
    try std.testing.expectEqual(reference_mod.RecoveryStatus.unsupported, recovery.snapshot().status);
    try std.testing.expectEqual(@as(u32, 1), recovery.snapshot().reference.linked.resource_schema_version);
    try std.testing.expect(recovery.active() == null);
}

test "resource recovery rejects trailing component state before starting work" {
    const TestResource = struct { value: u8 };
    const metadata_limit = 8;
    const TestFailure = enum { missing };
    const StrictRecovery = Recovery(struct {
        pub const Resource = TestResource;
        pub const Failure = TestFailure;
        pub const path_capacity = 32;
        pub const metadata_capacity = metadata_limit;
        pub const slot_capacity = 2;
        pub const maximum_work_units = 1;
        pub const maximum_result_units = 1;

        pub fn prepare(_: @import("path.zig").BoundedPath(path_capacity), _: *job_mod.WorkerContext) job_mod.Outcome(Prepared(Resource, metadata_capacity), Failure) {
            return .{ .failure = .missing };
        }

        pub fn destroy(resource: *Resource) void {
            std.heap.page_allocator.destroy(resource);
        }

        pub fn failureStatus(_: Failure) reference_mod.RecoveryStatus {
            return .missing;
        }
    });
    var bytes = [_]u8{ 0, 0xff };
    var reader = std.Io.Reader.fixed(&bytes);
    var recovery = StrictRecovery.init();
    defer recovery.deinit();
    try std.testing.expectError(error.TrailingResourceStateData, recovery.readComponentState(&reader));
    try std.testing.expectEqual(reference_mod.RecoveryStatus.empty, recovery.snapshot().status);
    try std.testing.expectEqual(@as(u64, 0), recovery.snapshot().generation);
}
