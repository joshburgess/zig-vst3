const std = @import("std");
const exchange_mod = @import("exchange.zig");
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
            if (publication != .published) {
                Config.destroy(prepared.resource);
            } else if (has_publication_ready) {
                Config.publicationReady(
                    request.preparation_context,
                    request.publication_generation,
                    publication_metadata,
                );
            }
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

        preparation: PreparationJob = .init(),
        exchange: Exchange = .{},
        completion: Completion = .{},
        clear_before_generation: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
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

        pub fn poll(self: *Self) void {
            const job_snapshot = self.preparation.snapshot();
            if (job_snapshot.generation == 0 or job_snapshot.generation == self.observed_job_generation) return;
            if (job_snapshot.status == .ready) _ = self.preparation.takeResult(job_snapshot.generation);
            if (job_snapshot.status == .ready or job_snapshot.status == .failed or job_snapshot.status == .cancelled) {
                self.observed_job_generation = job_snapshot.generation;
            }
        }

        pub fn waitAndPoll(self: *Self) void {
            self.preparation.wait();
            self.poll();
        }

        pub fn snapshot(self: *const Self) Snapshot {
            return self.completion.snapshot();
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
            self.next_publication_generation +%= 1;
            if (self.next_publication_generation == 0) self.next_publication_generation = 1;
            return self.next_publication_generation;
        }
    };
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
    recovery.waitAndPoll();
    const first_generation = recovery.snapshot().generation;
    try std.testing.expectEqual(first_generation, callbacks.generation.load(.acquire));
    try std.testing.expectEqual(@as(u32, 7), callbacks.value.load(.acquire));
    try std.testing.expectEqual(@as(?u32, 7), recovery.snapshot().publication_metadata);
    try std.testing.expect(!recovery.adoptPendingThroughAtBlockBoundary(first_generation - 1));
    try std.testing.expect(recovery.active() == null);
    try std.testing.expect(recovery.adoptPendingThroughAtBlockBoundary(first_generation));
    try std.testing.expectEqual(@as(u32, 7), recovery.active().?.value);

    try std.testing.expect(recovery.updatePreparationContext(.{ .multiplier = 3 }));
    recovery.waitAndPoll();
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
