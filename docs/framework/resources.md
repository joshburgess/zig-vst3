# Background Resources

`zig-vst3-plugin.resource` provides bounded preparation and lock-free publication for immutable DSP resources. It is intended for model graphs, impulse responses, wavetables, and similar data that must be prepared away from the audio thread.

The API is provisional. The Resource Swap example and the audio importer exercise the same job contract, but resource persistence and a model-oriented production consumer are still planned.

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

Validation commands:

```sh
ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build bundle-resource-swap validate-resource-swap
ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build test-resource-thread-sanitizer
```
