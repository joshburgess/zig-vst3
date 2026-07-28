# Background Resources

`zig-vst3-plugin.resource` provides bounded preparation, persistent references, recovery, and lock-free publication for DSP resources. Immutable data is the default. An opt-in ownership path supports mutable per-instance runtimes such as recurrent models.

The Resource Swap example exercises direct preparation and publication. The Model Shell exercises persistent references, asynchronous restoration, changed-file rejection, missing-file recovery, and relinking without an editor.

## Bounded paths

`BoundedPath(capacity)` owns a path in fixed inline storage. `init` rejects empty paths, embedded NUL bytes, and paths longer than `capacity`. Use it in job requests instead of retaining a file picker or drop callback slice.

```zig
const plug = @import("zig-vst3-plugin");
const ModelPath = plug.resource.BoundedPath(1024);

const path = try ModelPath.init(selected_path);
```

## Resource jobs

`resource.job.Job(Config)` owns one worker thread and one replaceable queued request. A configuration declares `Request`, `Result`, `Failure`, `maximum_work_units`, `maximum_result_units`, and a `run` function. It may also declare `maximum_runtime_nanoseconds` and `dispose`.

Requests must own their bounded input or refer only to storage whose lifetime is guaranteed until `deinit` joins the worker. `submit` replaces queued work and advances the generation. Running work observes the newer generation through `WorkerContext.cancellationRequested` and must stop cooperatively.

The worker operation reports its phase and bounded progress through `WorkerContext`:

- `setPhase` selects validation or loading.
- `setTotalUnits` establishes the fixed work bound.
- `advance` reports monotonic progress.
- `cancellationRequested` detects replacement, explicit cancellation, teardown, and the optional deadline.

`snapshot` copies status and progress without exposing the result. `takeResult` transfers an accepted result to the caller for the matching generation. Unclaimed or stale results are passed to `Config.dispose` when it is present.

Jobs may start during component initialization. An editor is not required. Call `deinit` before destroying any request storage or callback target. `deinit` cancels queued work, asks running work to stop, joins the worker, and disposes an unclaimed result.

## Persistent references

`resource.Reference(path_capacity, metadata_capacity)` stores four bounded values:

- A validated path in inline storage.
- The resource schema version.
- A small metadata summary for recovery UI.
- A stable identity containing the file length and SHA-256 digest.

`resource.ReferenceState` adds an explicit empty state. Its binary format is versioned and rejects oversized lengths before copying data. Model weights and file contents are not serialized.

`Identity.fromBytes` is convenient for small bounded files. `IdentityHasher` supports incremental hashing when a loader reads a larger resource in chunks. Identity calculation belongs in the background preparation operation, never in processing.

## Recovery

`resource.ResourceRecovery(Config)` combines a resource job, persistent reference, resource exchange, and synchronized status snapshot. `Config` supplies the resource type, bounds, preparation function, destructor, and failure classification.

The main entry points are:

- `importPath` accepts a new resource and identity.
- `restore` records saved state and starts preparation immediately.
- `relink` accepts a new path only when its content identity matches the saved resource.
- `snapshot` reports `empty`, `restoring`, `ready`, `missing`, `moved`, `changed`, `unsupported`, or `failed`.
- `adoptPendingAtBlockBoundary` makes a fully prepared resource visible to processing.
- `reclaim` destroys retired resources on a non-real-time thread.

The worker validates identity and schema compatibility before publication and updates recovery status without an editor polling loop. Restoring component state retires the previous active resource and any older pending publication at the next process-block boundary. Processing therefore remains safe and silent until the restored generation is ready. A missing, unsupported, or changed file remains recoverable. Changed content and incompatible schemas are not published, and the expected reference remains intact. An ordinary import or relink failure leaves the last valid active resource intact.

### Preparation context

A resource whose complete runtime depends on host configuration may declare a copyable `Config.PreparationContext` and `Config.initial_preparation_context`. Its `prepare` function then receives that value between the path and worker context arguments. Each request captures its own context value, so later changes cannot alter work already running.

Call `updatePreparationContext` from a non-real-time lifecycle callback when the host sample rate, maximum block size, or another preparation input changes. Recovery replaces any queued work and prepares the latest linked or in-flight source again. The existing active runtime remains valid until the audio thread adopts the replacement at a block boundary. Callers should avoid submitting an unchanged context because an update intentionally starts a new generation.

The context must own its bounded data by value. Do not put slices or pointers to temporary host callback storage in it. A pointer to a stable processor-owned mailbox is valid only when `deinit` joins the worker before that mailbox is destroyed. Model parsing, scratch allocation, sample-rate converter construction, and prewarming belong in `prepare`; the published runtime must need only bounded mutation during processing.

```zig
pub const PreparationContext = struct {
    host_rate: f64,
    max_block_size: u32,
};

pub const initial_preparation_context: PreparationContext = .{
    .host_rate = 48_000,
    .max_block_size = 4096,
};

pub fn prepare(
    path: ModelPath,
    preparation: PreparationContext,
    worker: *plug.resource.job.WorkerContext,
) plug.resource.job.Outcome(PreparedModel, Failure) {
    _ = path;
    _ = preparation;
    _ = worker;
    // Construct the complete runtime here.
    return .cancelled;
}
```

### Publication approval

A runtime that changes host-visible processing properties may also declare `Config.PublicationMetadata` and `Config.publicationMetadata`. Recovery copies this bounded value into its synchronized snapshot after successful publication. Control-side code can use it to update latency or another host contract without reading the mutable runtime.

`adoptPendingThroughAtBlockBoundary(generation)` leaves newer pending work untouched. A processor can therefore dispatch a host restart outside processing, publish the approved generation through an atomic value, and let the audio thread adopt only through that generation. If dispatch fails, the complete runtime remains pending and the previous active runtime remains owned by the audio thread.

An optional `Config.publicationReady(preparation_context, generation, metadata)` hook runs on the preparation worker after publication succeeds and before the job completes. It receives copied values, not the runtime pointer. This lets a stable processor-owned mailbox publish latency and generation atomically without waiting for an editor polling loop. The callback must remain bounded, must not access the transferred runtime, and must tolerate host-request failure without approving the generation.

The Model Shell uses publication metadata for host rate, maximum block size, and latency. Its completion callback approves a prepared model plus SRC runtime only after a required latency notification succeeds. Restoration and loading therefore work without an open editor. This is the ordering required for dynamically loaded fixed-rate processors.

Automatic directory scanning for moved files is intentionally excluded because it is unbounded and ambiguous. A caller supplies a candidate path through `relink`; matching content is recorded with the new path and a `moved` resolution.

### Controller resource commands

`zig-vst3.resource_path_transport` carries import, relink, cancel, and retry commands from an edit controller to its component. Import and relink messages contain at most 4,096 path bytes. Empty paths, embedded NUL bytes, oversized payloads, unknown commands, and wrong target IDs are rejected before a recovery object sees them. The receiver must still apply its own resource-specific path bound.

Declare one routed target on a `SimpleEffect` and return a compatible recovery receiver from the processor:

```zig
pub const resource_path_target_id = 1;

pub fn resourcePathReceiver(self: *Processor) *ModelRecovery {
    return &self.models;
}
```

An editor built with `ReflectedEditController` can call `importResourcePath`, `relinkResourcePath`, `cancelResourceImport`, and `retryResourceImport`. The VST3 message is delivered synchronously on the caller's non-real-time thread. Recovery copies a valid path into its own bounded request before notification returns, then performs file access and preparation on its worker. Do not call these helpers from processing, and do not retain the message payload in a custom receiver.

The Model Shell integration tests connect a real controller and component, import a valid model, relink identical content at a new path, retry malformed content, and reject cancellation when no job is active. This exercises the same public route that a future file picker or drop target will use.

The Model Shell also exposes recovery status, progress, cancellation and retry availability, and bounded model metadata through the retained GUI telemetry source. Numeric status and copied text snapshots remain readable after a failed replacement, while the last valid model and its metadata stay active. An editor can therefore present recovery state without sharing the recovery object, locking a runtime, or keeping the editor open during preparation. `ResourceRecovery.progressSnapshot` returns the bounded preparation job snapshot for this purpose.

Prefer `ResourceRecovery.presentationSnapshot` when one editor update needs status, progress, actions, and metadata together. It copies the recovery reference and reconciles the preparation job by generation. A stale job cannot enable Cancel or Retry for a newer request. Determinate progress is reported only after the matching worker publishes a nonzero work total. Earlier queued work uses an indeterminate running snapshot. Ready, failed, and empty recovery states map to validated toolkit-neutral progress states. The returned metadata remains owned by the snapshot, so callers must not retain its slice after discarding the snapshot.

The recovery object can be used as processor component state through these public processor declarations:

```zig
pub const component_state_maximum_encoded_size = Recovery.component_state_maximum_encoded_size;

pub fn writeComponentState(self: *const Processor, writer: anytype) !void {
    try self.resources.writeComponentState(writer);
}

pub fn readComponentState(self: *Processor, reader: anytype) !void {
    try self.resources.readComponentState(reader);
}
```

The VST3 shell wraps parameter and processor state in a bounded versioned envelope. Controllers read the parameter section and ignore processor-private bytes. Older parameter-only component state remains supported.

## Resource exchange

`resource.exchange.Exchange(Config)` transfers heap-owned immutable resources from one control-side writer to the audio thread. `Config` declares `Resource`, `slot_capacity`, and `destroy`.

The ownership sequence is:

1. The writer fully constructs a resource and calls `publish` with the next nonzero generation.
2. The audio thread calls `adoptPending` at a block boundary.
3. The audio thread reads the active resource through `active` for that block and later blocks.
4. Replacing or retiring the active resource marks its slot for reclamation.
5. A non-real-time thread calls `reclaim`, which invokes `Config.destroy`.

`publish` returns `Busy` when all fixed slots are in use. It returns `InvalidGeneration` for a stale generation. In both cases the caller still owns the unpublished pointer. Publishing a newer pending generation retires the older pending generation before audio adoption.

Generation comparisons use bounded serial-number ordering. A sequence may therefore advance from `maxInt(u64)` to `1` without making every later resource appear stale. Zero remains reserved for the uninitialized state, and generations separated by half the integer range are intentionally treated as unordered.

The writer stores a completed pointer before publishing the slot with release ordering. Audio adoption acquires the published slot and swaps the pending index at the block boundary. Retired slots are released by audio and acquired by the reclaimer before destruction. `active_slot` is owned by the audio thread while processing is live.

`adoptPending`, `active`, and `retireActiveAtBlockBoundary` do not allocate, lock, destroy resources, access files, or call the host. `publish`, `reclaim`, and `deinit` are non-real-time operations.

### Mutable runtimes

Set `Config.mutable_active = true` when processing must update per-instance state inside a prepared runtime. `activeMutable` then returns the exclusively adopted pointer:

```zig
const RuntimeExchange = plug.resource.exchange.Exchange(struct {
    pub const Resource = ModelRuntime;
    pub const slot_capacity = 4;
    pub const mutable_active = true;

    pub fn destroy(runtime: *ModelRuntime) void {
        allocator.destroy(runtime);
    }
});
```

The ownership rules are stricter than ordinary shared immutable data:

- A successful `publish` transfers ownership. The publishing thread must not retain or access the runtime.
- Only the audio thread may call `adoptPending`, `activeMutable`, or `retireActiveAtBlockBoundary` while processing is live.
- The mutable pointer is valid until that audio thread replaces or retires it at a later block boundary. Do not cache it past that boundary.
- Construction, allocation, model prewarming, and destruction stay off the audio thread. A runtime reset method may run on the audio thread only when it is bounded, allocation-free, and lock-free.
- UI and control threads read synchronized status or immutable metadata. They must not inspect mutable inference state while processing.

`ResourceRecovery` exposes the same opt-in path through `Config.mutable_active = true` and `activeMutable`. Its persistence format still stores only the bounded resource reference.

## Shutdown order

Use this order when a processor owns both a job and an exchange:

1. Stop new submissions.
2. Call `Job.deinit` to cancel and join preparation.
3. Stop or deactivate audio processing.
4. Call `retireAllAfterProcessingStops`.
5. Call `Exchange.deinit` to reclaim remaining resources.

Do not call `retireAllAfterProcessingStops` while the audio thread can still read the active resource.

## Reference implementation

`examples/resource_swap_core.zig` prepares a bounded dummy graph in the background, publishes it through a four-slot exchange, adopts it at a mono process block boundary, and reclaims the replaced graph off-thread. Its processor starts preparation during initialization and has no editor dependency.

`examples/model_shell_core.zig` loads and prewarms a bounded versioned JSON linear runtime. The worker combines the model, host-to-model and model-to-host converters, and fixed scratch for both sample formats before publication. It persists only the path, identity, schema version, and metadata summary. Its stateful recurrence proves mutable block-to-block state and real-time reset after exclusive adoption. Tests also cover context-dependent rebuilding, latency-approved adoption, restoration without an editor, safe silence for a missing resource, changed-content rejection, and matching-content relinking.

Validation commands:

```sh
ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build bundle-resource-swap validate-resource-swap
ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build bundle-model-shell validate-model-shell
ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build test-resource-thread-sanitizer
```
