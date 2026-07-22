# Background Resources

`zig-vst3-plugin.resource` provides bounded preparation, persistent references, recovery, and lock-free publication for immutable DSP resources. It is intended for model graphs, impulse responses, wavetables, and similar data that must be prepared away from the audio thread.

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

`resource.ResourceRecovery(Config)` combines a resource job, persistent reference, immutable exchange, and synchronized status snapshot. `Config` supplies the resource type, bounds, preparation function, destructor, and failure classification.

The main entry points are:

- `importPath` accepts a new resource and identity.
- `restore` records saved state and starts preparation immediately.
- `relink` accepts a new path only when its content identity matches the saved resource.
- `snapshot` reports `empty`, `restoring`, `ready`, `missing`, `moved`, `changed`, `unsupported`, or `failed`.
- `adoptPendingAtBlockBoundary` makes a fully prepared resource visible to processing.
- `reclaim` destroys retired resources on a non-real-time thread.

The worker validates identity and schema compatibility before publication and updates recovery status without an editor polling loop. Restoring component state retires the previous active resource and any older pending publication at the next process-block boundary. Processing therefore remains safe and silent until the restored generation is ready. A missing, unsupported, or changed file remains recoverable. Changed content and incompatible schemas are not published, and the expected reference remains intact. An ordinary import or relink failure leaves the last valid active resource intact.

Automatic directory scanning for moved files is intentionally excluded because it is unbounded and ambiguous. A caller supplies a candidate path through `relink`; matching content is recorded with the new path and a `moved` resolution.

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

## Immutable exchange

`resource.exchange.Exchange(Config)` transfers heap-owned immutable resources from one control-side writer to the audio thread. `Config` declares `Resource`, `slot_capacity`, and `destroy`.

The ownership sequence is:

1. The writer fully constructs a resource and calls `publish` with a strictly increasing nonzero generation.
2. The audio thread calls `adoptPending` at a block boundary.
3. The audio thread reads the active resource through `active` for that block and later blocks.
4. Replacing or retiring the active resource marks its slot for reclamation.
5. A non-real-time thread calls `reclaim`, which invokes `Config.destroy`.

`publish` returns `Busy` when all fixed slots are in use. It returns `InvalidGeneration` for a stale generation. In both cases the caller still owns the unpublished pointer. Publishing a newer pending generation retires the older pending generation before audio adoption.

The writer stores a completed pointer before publishing the slot with release ordering. Audio adoption acquires the published slot and swaps the pending index at the block boundary. Retired slots are released by audio and acquired by the reclaimer before destruction. `active_slot` is owned by the audio thread while processing is live.

`adoptPending`, `active`, and `retireActiveAtBlockBoundary` do not allocate, lock, destroy resources, access files, or call the host. `publish`, `reclaim`, and `deinit` are non-real-time operations.

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

`examples/model_shell_core.zig` loads a bounded versioned JSON linear model. It persists only the path, identity, schema version, and metadata summary. Tests cover state restoration without an editor, safe silence for a missing resource, changed-content rejection, and matching-content relinking.

Validation commands:

```sh
ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build bundle-resource-swap validate-resource-swap
ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build bundle-model-shell validate-model-shell
ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build test-resource-thread-sanitizer
```
