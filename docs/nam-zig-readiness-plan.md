# Zig NAM Readiness Plan

## Purpose

Use the Rust Neural Amp Modeler port as a concrete production workload for deciding what `zig-vst3` and `zig-vst3-plugin` need next. This plan does not authorize a NAM rewrite. It identifies reusable prerequisites, keeps model-specific code out of the plugin framework, and defines smaller proving milestones.

The audit used `nam-rs` commit `26cd9412567d397d8af395977732659100d9b26b` on its `main` branch.

## Architectural conclusion

A Zig NAM implementation should have three layers:

1. `zig-vst3` owns VST3 ABI behavior, host negotiation, bus layouts, latency reporting, restart requests, and platform integration.
2. `zig-vst3-plugin` owns safe plugin-authoring patterns: parameters, state, background resource jobs, prepared resource publication, exclusive mutable runtime adoption, real-time-safe reclamation, resampling, and reusable model-loader UI.
3. A separate `zig-nam` library owns the `.nam` format, model validation, tensors, inference graphs, neural layers, optimized kernels, reference fixtures, and headless processing API.

The third layer must not import VST3 or GUI code. It should be usable by a command-line renderer, tests, benchmarks, and other plugin formats.

## What the reference workload requires

`nam-rs` is more than a plugin with a file picker. Its core supports Linear, ConvNet, LSTM, WaveNet, Sequential, and slimmable model configurations. The implementation includes dynamic JSON model construction, persistent recurrent and convolution state, model metadata, prewarming, optional sample-rate conversion, and small-matrix optimized kernels.

Its plugin adds:

- Mono audio input and output.
- Asynchronous `.nam` loading and model restoration from a path.
- Input and output gain smoothing.
- A selectable fast activation mode.
- Host-rate to model-rate conversion and back.
- VST3 and CLAP exports.

The current Rust plugin is useful as a requirements source, but not as a real-time design template. Its process callback locks the shared model, copies an input block on the resampled path, and may grow vectors and deques. A Zig implementation must replace those behaviors with bounded, ownership-safe mechanisms.

## Current readiness

### Capabilities already present

- Reflected continuous, discrete, boolean, and enum parameters.
- Sample-accurate parameter changes and MIDI/event input.
- Linear, exponential, and logarithmic parameter smoothing.
- `f32` and `f64` process entry points with bounded channel views.
- Processor preparation, reset, teardown, instance isolation, and real-time auditing.
- Fixed latency and tail queries through optional processor methods.
- File drop and keyboard-accessible file selection.
- Bounded path validation, cancellation, progress, retry, and stale-generation handling.
- Background WAV and AIFF decoding with atomic publication to the Sample Player and IR Loader.
- Toolkit-neutral status, progress, graph, telemetry, preset, and responsive-layout components.
- Raw C and C++ compilation and linking in this repository's build graph.
- Deterministic tests, ABI checks, validators, cross-target bundles, visual tests, sanitizers, and benchmarks.

These facilities now cover the reusable plugin-framework side of a NAM editor and processor. Model parsing, tensor ownership, inference execution, and model-specific kernels remain work for a separate `zig-nam` library.

### Important gaps

| Capability | Current state | Required home | Priority |
| --- | --- | --- | --- |
| Configurable audio layouts | Mono, stereo, absent, and mixed main-bus layouts are public and validated | `zig-vst3` and `zig-vst3-plugin` | Complete |
| Immutable model publication | Fixed-capacity immutable resource exchange implemented and validated | `zig-vst3-plugin` | Complete |
| Mutable inference runtime | Opt-in exclusive audio-thread mutation after block-boundary adoption implemented and validated | `zig-vst3-plugin` | Complete |
| Deferred destruction | Replaced resources retire on audio and are reclaimed off-thread | `zig-vst3-plugin` | Complete |
| Generic background resource jobs | Bounded replaceable jobs implemented and used by the audio importer | `zig-vst3-plugin` | Complete |
| Context-dependent runtime preparation | Copyable host preparation context is captured per recovery generation and linked resources can be rebuilt off-thread | `zig-vst3-plugin` | Complete |
| Streaming sample-rate conversion | Bounded streaming SRC and fixed-rate round-trip pipeline implemented and validated | Reusable DSP package, surfaced through `zig-vst3-plugin` | Complete |
| Dynamic latency notification | Public coalesced component-to-controller restart path implemented and compatible with restored processor resource state | `zig-vst3` and `zig-vst3-plugin` | Complete |
| Resource persistence | Bounded reference state, stable identity, asynchronous recovery, and relinking implemented | `zig-vst3-plugin` | Complete |
| Consumer C kernel integration | Public downstream recipe, installed-package test, and portable plus architecture-specific probe implemented | Package build API and DSP library | Complete |
| CPU dispatch | Per-instance runtime NEON and AVX2 selection with a portable baseline implemented | DSP library | Complete |
| Activation quality isolation | Automatable per-instance selection is stored on the exclusively owned runtime | Plugin parameters and prepared runtime | Complete |
| Denormal policy | Scoped process-thread FTZ/DAZ or FZ with exact restoration implemented | `zig-vst3-plugin` or DSP library | Complete |
| Headless golden rendering | Reusable fixed and randomized block runner with generated C++ WAV references implemented | Framework test tooling and future `zig-nam` tooling | Complete |
| CLAP export | Out of scope for a VST3 backend | Separate backend or toolkit-neutral plugin shell | Later decision |

## P0 framework milestones

### 1. Configurable main bus layouts

- [x] Replace stereo-only booleans with a bounded declarative bus-layout API.
- [x] Support at least mono, stereo, mono-to-stereo, generator, and analyzer layouts without weakening existing defaults.
- [x] Expose negotiated channel counts to preparation and processing code.
- [x] Reject unsupported arrangements transactionally and report the preferred arrangement.
- [x] Add processor, ABI, validator, and cross-target coverage for a mono effect.

Exit criteria:

- A public-API-only mono effect passes Steinberg validation in both sample formats.
- Existing stereo, generator, and analyzer plugins retain their behavior.
- Process views never expose more channels than the negotiated layout.

Completion evidence:

- `AudioBusLayout` declares `.none`, `.mono`, and `.stereo`. `PluginSpec` retains stereo defaults and maps the older audio-presence flags without allowing conflicting declarations.
- The public `Mono Gain` probe uses `@import("zig-vst3-plugin")` for its core declaration and the public `SimpleEffect` VST3 shell. It rejects stereo arrangements and bounds process views to one channel.
- The Steinberg validator passed all 47 tests, including single-precision and double-precision mono processing, variable blocks, arrangement fallback, and state transitions.
- The full deterministic suite passed 3,962/3,962 tests. Raw ABI, entry-symbol, installed-package, native adapter, macOS accessibility, visual regression, and sanitizer gates passed.
- All 15 examples passed native Steinberg validation. Linux aarch64 and Windows x86_64 cross-target matrices each passed 47/47 build steps. Cross-compilation remains build coverage rather than native host verification.

### 2. Generic bounded resource jobs

- [x] Extract the shared lifecycle from the audio importer: idle, validating, loading, ready, cancellation, failure, retry, and replacement.
- [x] Make decoding or parsing a caller-supplied worker operation with explicit byte, time, and result limits.
- [x] Support jobs that begin during component initialization without an open editor.
- [x] Separate status snapshots from the loaded resource so the GUI never locks the resource owner.
- [x] Preserve generation checks and reject stale completion callbacks after replacement or teardown.

Exit criteria:

- A test plugin loads a bounded non-audio fixture through drop, picker, and restored state.
- Cancellation and teardown join or reject all pending work without callbacks into destroyed instances.
- The audio thread never performs file access, allocation, logging, or host calls.

Completion evidence:

- `resource.job.Job` provides bounded requests, caller-defined work, result and runtime limits, cooperative cancellation, replacement, retry, snapshots, result transfer, and disposal of stale or unclaimed results.
- Deterministic fixture tests exercise drop, picker, and restored-state source paths, replacement, stale completion, cancellation, teardown, deadlines, and work and result limits.
- The existing WAV and AIFF importer now uses the shared job lifecycle while retaining its detailed format and recovery states.
- The Resource Swap processor starts a job during component initialization and does not depend on an open editor.

### 3. Resource exchange and reclamation

- [x] Design a single-writer publication primitive for heap-owned immutable resources.
- [x] Let the audio thread adopt a complete model at a block boundary without a mutex.
- [x] Support exclusive mutation of adopted recurrent or convolution runtime state without exposing it to control threads.
- [x] Return replaced resources to a non-real-time reclaimer without reference-count destruction on the audio thread.
- [x] Define behavior when publication slots are full, a model is replaced repeatedly, or processing stops during a swap.
- [x] Make ownership, memory ordering, and maximum outstanding resources explicit in the API.

Exit criteria:

- Generated lifecycle tests cover publish, adopt, replace, cancel, reset, stop, and destroy sequences.
- Thread and address sanitizers pass repeated concurrent publication tests.
- A real-time audit proves process-time operations are bounded and allocation-free.

Completion evidence:

- `resource.exchange.Exchange` uses fixed publication slots, strictly increasing generations, single-writer publication, block-boundary adoption, and explicit off-thread reclamation.
- Immutable access remains the default. `Config.mutable_active = true` enables exclusive audio-thread mutation after adoption. Successful publication transfers ownership, and the pointer expires when the audio thread replaces or retires that generation at a block boundary.
- Tests cover publication, immutable and mutable adoption, pending replacement, stale generations, full capacity, processing stop, destruction, real-time auditing, and 1,000 concurrent replacements.
- `docs/framework/resources.md` specifies pointer ownership, release and acquire ordering, slot limits, failure ownership, and shutdown order.
- The mono Resource Swap probe adopts an immutable prepared graph. The Model Shell publishes a prewarmed stateful runtime, preserves its recurrence across blocks, resets it without allocation or locking, and reclaims replaced runtimes off-thread.
- The deterministic suite, raw ABI checks, installed-package consumer, and 24-test resource thread-sanitizer target pass. The stateful Model Shell passes all 47 Steinberg validator tests in both sample formats and cross-builds for Linux aarch64 and Windows x86-64.
- Linux aarch64 and Windows x86_64 cross-target matrices each passed 50/50 build steps, including the Resource Swap bundle. Native Windows and Linux host execution remains unavailable.

### 4. Bounded streaming sample-rate conversion

- [x] Select or build a resampler with known quality, latency, and licensing.
- [x] Allocate all filter state, queues, and scratch storage during preparation.
- [x] Handle arbitrary host block sizes without growing storage.
- [x] Define startup, drain, reset, discontinuity, and sample-rate-change behavior.
- [x] Report exact round-trip latency and preserve dry/wet alignment where relevant.
- [x] Benchmark common NAM rate pairs, especially 44.1, 48, 88.2, and 96 kHz.

Exit criteria:

- No process path allocates, locks, or changes capacity.
- Impulse, sine, sweep, and randomized block tests verify latency, continuity, bounded error, and deterministic reset.
- A fixed-rate probe plugin passes variable-block and state-transition validator tests.

Completion evidence:

- `dsp.StreamingResampler` uses a 32-tap, 256-phase Blackman-windowed sinc filter with fixed inline coefficients and history. It supports partial consumption, explicit drain, deterministic reset, finite rate bounds, and `f32` and `f64` processing.
- `dsp.FixedRatePipeline` owns both conversion stages, ten frames of bounded pending storage, exact integer host latency, and caller-owned model scratch sized through `requiredModelCapacity`.
- Impulse, passband sine, stopband sine, randomized block, reset, drain, invalid-state, and insufficient-capacity tests pass.
- The public Fixed Rate Processor runs a 48 kHz trivial model and passes all 47 Steinberg validator tests, including variable blocks, both sample formats, lifecycle transitions, and unusual validator rates.
- The two-stage pipeline measured 44.7, 42.5, 32.6, and 30.0 ns per host sample at 44.1, 48, 88.2, and 96 kHz respectively on the current macOS development machine.
- The aggregate suite passed 4,016/4,016 tests. Raw ABI checks, native VSTGUI sanitizers, and all 17 Steinberg validators passed.
- Linux aarch64 and Windows x86_64 cross-target matrices each passed 53/53 build steps with the Fixed Rate Processor bundle.

### 5. Runtime latency and restart contract

- [x] Expose a public processor-to-controller request for `kLatencyChanged`.
- [x] Define when a newly loaded model or SRC configuration becomes active relative to the reported latency.
- [x] Coalesce redundant restart notifications outside the audio callback.
- [x] Test latency before activation, after preparation, and after prepared-mode replacement.

Exit criteria:

- A probe plugin changes between two prepared latency modes without calling the host from processing.
- The host-visible latency and active processing path change in a documented order.
- State restore and repeated activation do not leave stale latency.

Completion evidence:

- `HostRequestSink` is bound through the optional processor `bindHostRequests` hook. Atomic marks coalesce, while dispatch is rejected from a real-time audit scope before any host call.
- The component sends a bounded message to its connected controller. The controller calls `restartComponent` with `kLatencyChanged`.
- The Fixed Rate Processor publishes the new latency, dispatches the restart outside processing, and makes the prepared mode eligible for adoption only after successful dispatch. The audio thread adopts and resets at its next block boundary.
- Unit tests verify one restart for repeated marks, host-visible latency before audio adoption, mode toggles, and repeated preparation at different host rates.
- The Fixed Rate Processor persists its prepared-mode choice through the component-state envelope. Restoration before preparation selects the matching processing path and exact latency, while the controller reads the parameter section independently.

### 6. Resource state and recovery

- [x] Add bounded non-parameter component state for a resource path, stable identity, metadata summary, and schema version.
- [x] Do not serialize model weights into ordinary plugin state by default.
- [x] Define missing, moved, changed, and unsupported resource behavior.
- [x] Reload restored resources asynchronously and keep the plugin safe and silent until publication completes.
- [x] Provide a relink action and accessible status without requiring the editor to remain open.

Exit criteria:

- State round trips without truncating a valid maximum-length path.
- Missing files restore to a recoverable state instead of failing component initialization.
- A changed file cannot silently reuse metadata from an older model generation.

Completion evidence:

- `resource.Reference` stores a bounded path, SHA-256 identity, byte length, schema version, and bounded metadata summary. `ReferenceState` represents empty and linked resources in a versioned binary format.
- The VST3 component-state envelope preserves legacy parameter-only state, exposes processor-owned bounded state through public hooks, and lets controllers restore the parameter section without parsing processor-private data.
- `resource.ResourceRecovery` starts restoration on its worker, verifies identity and schema compatibility before publication, publishes without an editor polling loop, and reports explicit missing, moved, changed, unsupported, and failed states. A restore retires the previous active resource and any older pending generation at the next process-block boundary.
- The Model Shell loads a small versioned JSON linear model and processes mono audio. Its tests prove maximum-path state round trips, editor-independent restoration, safe silence while missing, changed-file rejection, matching-content relinking, and controller compatibility.
- The preparation worker owns all file access, JSON parsing, hashing, allocation, SRC construction, scratch sizing, prewarming, and destruction. Processing only adopts a fixed-slot publication and mutates its exclusively owned runtime state.
- The aggregate deterministic suite, raw ABI checks, VSTGUI address and undefined-behavior sanitizers, resource thread sanitizer, and all 19 Steinberg validators pass. The Model Shell and Fixed Rate Processor each pass all 47 validator tests in both sample formats.
- Linux aarch64 and Windows x86_64 cross-target matrices each build all 19 example bundles. These are build checks, not native host validation.
- On the current macOS development machine, bounded reference state save and load measured 38.9 ns per round trip, and 4 KiB SHA-256 identity generation measured 2,503.8 MiB/s.

## P1 reusable infrastructure

### Context-dependent runtime preparation

- [x] Let a recovery configuration declare bounded per-instance preparation inputs such as host rate and maximum block size.
- [x] Capture the context by value in each worker request.
- [x] Replace queued work and rebuild the latest linked or in-flight source when the context changes.
- [x] Keep the active runtime valid until block-boundary adoption of the replacement.

Completion evidence:

- `resource.ResourceRecovery` accepts an optional `PreparationContext` with an explicit initial value. Existing configurations retain their two-argument preparation function and behavior.
- `updatePreparationContext` starts a new generation for the latest source. The worker sees an owned snapshot, stale work is cancelled, and publication still passes through identity and schema validation.
- Deterministic tests prove that the previous runtime remains active while context-specific preparation runs, then retires only after block-boundary adoption. Reclamation remains off the audio thread.
- Optional bounded publication metadata lets control-side code inspect host-visible properties without touching a mutable runtime. Generation-limited adoption leaves newer work pending until its host contract is approved.
- An optional post-publication callback receives only copied context, generation, and metadata. The Model Shell uses a stable processor-owned atomic mailbox to dispatch latency and approve background restoration without an editor polling loop.
- The Model Shell now composes file-declared model rate, per-instance host rate and maximum block size, stateful inference, both sample formats, fixed scratch, exact SRC latency, and host restart ordering. A mismatched old runtime stays silent, and a replacement cannot be adopted before successful latency dispatch.
- The Model Shell passes all 47 Steinberg validator tests. The full deterministic suite, raw ABI checks, and resource ThreadSanitizer pass. Linux aarch64 and Windows x86-64 example matrices cross-build successfully.
- Generated lifecycle coverage performs 32 file and preparation-context replacements across 44.1, 48, 88.2, and 96 kHz. It alternates sample formats, randomizes blocks from 1 to 257 frames, checks finite output and exact reset reproduction, and reclaims retired runtimes off-thread.
- Another 32 iterations destroy the processor immediately after submitting preparation. Each teardown cancels or joins its worker before runtime storage is destroyed.
- The existing release benchmark covers the shared SRC hot path. This run measured 33.3 to 48.7 ns per host sample across the four host rates, within the 2,000 ns per sample regression budget. Model-specific inference benchmarks remain work for `zig-nam`.

### Controller-to-processor resource commands

- [x] Add a fixed-capacity VST3 message contract for import and relink paths.
- [x] Route cancel and retry without exposing adapter internals to editor code.
- [x] Reject malformed, oversized, embedded-NUL, unknown-target, and unsupported commands deterministically.
- [x] Exercise the public contract through a connected Model Shell controller and component.

Completion evidence:

- `resource_path_transport` owns at most 4,096 path bytes per stack message and uses explicit target IDs. A recovery receiver applies its narrower model-specific path capacity before submitting work.
- `ReflectedEditController` exposes import, relink, cancel, and retry helpers. `SimpleEffect` routes them through an optional `resource_path_target_id` and processor `resourcePathReceiver` without adapter-internal imports in plugin code.
- Model Shell tests import a valid model, relink matching content, retry a malformed model, and verify idle cancellation rejection through actual VST3 connection points. File access, parsing, allocation, and runtime preparation remain on the recovery worker.
- The retained telemetry source copies bounded status and metadata text into controller-owned buffers and exposes progress, cancellation, and retry availability as scalar snapshots. Model Shell tests verify ready and failed status, preserved active metadata after replacement failure, deterministic truncation, and action availability.
- `ResourceRecovery.presentationSnapshot` now reconciles recovery and worker generations before exposing status, progress, Cancel, Retry, cancellation, and metadata. Model Shell telemetry uses that single contract, and deterministic tests cover active progress, cancellation, retry, success, and installed-package consumption.
- All message transports reject a null host-provided message ID through the shared raw API helper. The raw plug-view, parameter-function, program-info, and attribute-list interfaces also represent host-provided C strings as nullable and reject null before decoding. Failed attribute reads clear their outputs so malformed host calls cannot expose stale values.
- The full deterministic suite passes 4,094 tests, including the connected controller/component integration. The Model Shell continues to pass all 47 Steinberg validator tests.

### Public C kernel integration

- [x] Document how a downstream package adds portable C sources, include paths, compile flags, and target-specific objects to a plugin bundle.
- [x] Provide a small reference kernel with a Zig fallback and C differential tests.
- [x] Keep `-ffast-math` scoped to explicitly selected kernels. Do not apply it to the whole plugin or model parser.
- [x] Verify macOS universal, Linux, and Windows builds, including symbol visibility and allocator boundaries.

Zig makes direct C interoperability natural, but integration is only an advantage if downstream builds can use it without copying this repository's internal build functions.

Completion evidence:

- `docs/framework/c-kernels.md` contains the downstream `std.Build` recipe, target-specific source selection, runtime dispatch contract, and allocator ownership rules. `tests/installed-consumer` stages the installed package separately, builds a dynamic plugin with consumer-owned C code, and tests caller-owned buffers.
- The C Kernel Probe provides the same fixed 4x4 dense operation in Zig, portable C, NEON, and AVX2. Identical fixtures compare the portable implementation at `1e-6` absolute error and accelerated implementations at `1e-5`.
- Only `dense_neon.c` and `dense_avx2.c` receive `-ffast-math`. Portable C, Zig code, plugin glue, and resource parsing retain their normal floating-point settings.
- `zig build test-c-kernel-builds` produces a universal macOS bundle with arm64 and x86_64 slices, Linux aarch64 and x86-64 bundles, and a Windows x86-64 bundle. Mach-O, ELF, and PE export-table checks reject public `zig_vst3_dense4_*` symbols while requiring the platform VST3 entry points.
- Every C entry point consumes caller-owned fixed buffers, retains no pointer, and performs no allocation. The real-time audit verifies allocation-free mono block processing.
- The aggregate deterministic suite, installed-package test, raw ABI gate, and all 47 C Kernel Probe Steinberg validator tests pass locally.

### CPU feature dispatch

- [x] Define a portable baseline kernel set.
- [x] Add runtime selection for supported accelerated variants where distribution targets require it.
- [x] Keep dispatch outside inner loops and make the chosen kernel observable in diagnostics.
- [x] Compare Zig, portable C, and accelerated C implementations with identical fixtures.

Completion evidence:

- `dsp.kernel_dispatch` reports native NEON and AVX2 support and maps an explicit feature set to a backend without global mutable state.
- Each C Kernel Probe processor selects and stores its backend and function pointer during instance initialization. The audio loop calls that pointer directly, and `kernelBackendName` exposes the choice for diagnostics.
- The portable C implementation is always built. Architecture-specific objects are selected by the build target, then guarded by runtime detection before use.
- On the current arm64 macOS machine, the release benchmark measured 1.3 ns per fixed 4x4 operation for Zig, 2.2 ns for portable C, and 1.4 ns for NEON C over 400,000 iterations. These figures are local regression measurements, not cross-machine guarantees.
- An x86-64 macOS build runs under Rosetta and correctly keeps the portable backend selected when AVX2 is not reported. Native AVX2 execution remains pending on x86-64 hardware. The AVX2 object currently has compile, link, and export coverage; its identical-fixture test runs only when runtime detection reports AVX2.

### Denormal handling

- [x] Decide between scoped processor-thread FTZ/DAZ, numerically safe noise, or architecture-neutral algorithmic avoidance.
- [x] Restore any modified floating-point environment when required by the host contract.
- [x] Add silence-tail performance tests for recurrent and convolution workloads.

Completion evidence:

- `dsp.DenormalScope` uses scoped FTZ and DAZ on x86-64 and scoped FZ on aarch64. It avoids noise injection so silence and parity renders remain deterministic. Unsupported architectures receive an explicit no-op scope and must use algorithmic avoidance.
- The scope reads the processor thread's existing MXCSR or FPCR value, changes only the required flush bits, and restores the exact saved value on `leave`. Nested scopes preserve the outer scope, and an already-enabled host policy remains unchanged.
- Native arm64 tests and x86-64 tests under Rosetta verify scope entry, subnormal result flushing, nesting, and exact restoration. The same module compiles for Linux aarch64/x86-64 and Windows x86-64.
- Strict C benchmark workloads prevent ReleaseFast constant folding. On the current arm64 macOS machine, a 32-step recurrent silence tail measured 0.3 ns per state update and a 16-tap convolution silence tail measured 2.1 ns per output sample with the scope active. Both remain below their regression budgets.

### Per-instance activation quality

- [x] Replace the reference plugin's process-global quality switch with an automatable per-instance contract.
- [x] Apply quality changes at a process-block boundary without allocation, locking, or resource rebuilding.
- [x] Apply offset-zero changes to the current block and defer later changes to the next block.
- [x] Prove that changing one plugin instance cannot affect another instance.

Completion evidence:

- The Model Shell exposes a reflected `Fast Activation` boolean parameter. The VST3 shell gives block-rate processors an offset-zero state snapshot while persisting the final queue value for the next block.
- Each adopted `PreparedRuntime` owns its `ActivationQuality`. The audio thread updates that field only after exclusive block-boundary adoption, so no global mutable quality state exists.
- Public `process.BlockParameterLatch` prevents the shell's persisted final queue value from making a structural change take effect before its sample offset. The latest offset-zero value applies to the current block, while later values become eligible at the next block.
- A deterministic two-instance test loads the same model into both processors, selects different quality modes, and verifies independent runtime state before and after changing one instance.
- A deterministic timing test verifies deferred and offset-zero quality changes, and the installed-package consumer compiles and runs the public latch contract.
- The Model Shell passes all 47 Steinberg validator tests with automated parameter changes in both sample formats.
- The aggregate suite passes 4,132 tests, and the installed-package suite passes 7 tests. Raw ABI checks and Linux aarch64 and Windows x86-64 example bundle matrices also pass.

### Headless DSP fixture runner

- [x] Define a host-independent block processor test interface.
- [x] Feed WAV fixtures with fixed and randomized block boundaries.
- [x] Compare output against C++ reference renders with documented absolute, relative, and aggregate error limits.
- [x] Record performance by architecture, model, sample format, sample rate, and kernel backend.

Completion evidence:

- `dsp.BlockProcessor(Sample)` provides a host-independent mono `reset` and `processBlock` contract. `fixture_runner` renders caller-owned buffers with fixed or deterministically randomized block boundaries and does not allocate during rendering.
- The bounded in-memory WAV decoder accepts mono PCM16, IEEE f32, and IEEE f64 fixtures. Unit tests cover format validation, truncated input, output capacity, and identical stateful results across block patterns.
- Truncated-prefix and near-valid mutation tests exercise every byte of a valid fixture. The installed-package consumer compiles and runs the public rendering and comparison API from a staged package.
- `zig build test-dsp-fixtures` compiles a C++17 reference renderer, generates 8,192-frame 48 kHz fixtures, and compares Zig f32 and f64 output using maximum absolute, maximum relative, and RMS limits. Pointwise acceptance uses the documented absolute-or-relative rule, followed by an aggregate RMS limit.
- Native arm64 macOS measured 1.6 to 2.4 ns per sample with exact reference output. The x86-64 binary under Rosetta measured 1.7 to 2.4 ns per sample. Its maximum errors were 2.98e-7 for f32 and 5.56e-16 for f64. Fixed and randomized renders remained bit-identical. The runner reports architecture, model, format, rate, backend, timings, and error metrics, and enforces a 100 ns per sample regression ceiling.
- These x86-64 numbers are translated execution, not native x86-64 validation. Native Linux and Windows performance remain external checks.

## Work that belongs in `zig-nam`

The following capabilities should not be added to `zig-vst3` or the general plugin framework:

- Bounded `.nam` JSON parsing and schema/version validation.
- Model metadata and architecture dispatch.
- Tensor and matrix ownership, shapes, layouts, and checked indexing.
- Ring buffers and scratch planning for model inference.
- Linear, Conv1d, Conv1x1, LSTM, WaveNet, Sequential, and slimmable layers.
- FiLM, gated activation, blended activation, and activation approximations.
- Portable Zig kernels and optimized C kernels.
- Model prewarming and recurrent-state reset.
- C++ parity fixtures, numerical tolerances, and architecture-specific benchmarks.
- A headless library API and offline rendering command.

The core API should accept prepared scratch memory and process caller-owned slices. Parsing, allocation, model construction, and prewarming happen off the audio thread. Inference must never know about VST3 parameters, GUI state, or host callbacks.

## Recommended proving plugins

Build these before starting a Zig NAM port:

1. **Mono Layout Probe**: a public-API-only mono gain effect that proves bus negotiation and channel views.
2. **Resource Swap Probe**: asynchronously load a bounded dummy graph, publish it lock-free, replace it under continuous processing, and reclaim it off-thread.
3. **Fixed-Rate Processor**: run a trivial gain model at a declared model rate through the streaming SRC and verify latency changes.
4. **C Kernel Probe**: ship portable Zig and C implementations of a small matrix operation with runtime selection, differential tests, and cross-target bundles.
5. **Model Shell**: load a tiny versioned JSON linear model, restore its resource state, expose metadata in the GUI, and process mono audio. This exercises the complete framework contract without implementing NAM.

Only after all five probes pass should a `zig-nam` repository or package begin implementing the actual model architectures.

## Design constraints carried into future work

- No mutex, allocation, capacity growth, file access, logging, GUI callback, host callback, or final resource destruction on the audio thread.
- Quality or fast-activation selection is per plugin instance or per published model. It is not a process-global switch.
- Large immutable models may use off-thread heap allocation. Fixed capacity applies to handoff slots, queues, scratch plans, and resource count, not necessarily to every model byte.
- A failed manual import or relink keeps the last valid model active. Restoring different component state retires the previous model at a block boundary and remains silent until the restored resource is ready.
- Model replacement becomes visible atomically at a documented block boundary.
- Sample-rate conversion latency is explicit and host-visible.
- Cross-compilation is build coverage, not native host verification.
- CLAP support is a separate backend decision. It should not distort VST3-specific APIs.

## Validation matrix for each prerequisite

- [x] Deterministic unit and generated lifecycle tests.
- [x] Real-time audit and allocation checks.
- [x] Address, undefined-behavior, and thread sanitizers where supported.
- [x] Raw VST3 ABI checks for any backend change.
- [x] Steinberg validator in both sample formats.
- [x] Linux aarch64 and Windows x86_64 cross-target bundles.
- [ ] Native macOS host lifecycle checks when practical.
- [x] Performance measurements with fixed fixtures and recorded machine context.
- [x] Documentation of unavailable native Windows, X11, Wayland, and CLAP coverage.

Local validation on 2026-07-22:

- `zig build test`, including installed-package consumers, native adapter tests, macOS accessibility tests, visual regression, and the DSP parity runner, passed.
- `zig build raw-api-abi` passed.
- `zig build validate-examples` passed all 47 Steinberg tests for every example in both sample formats.
- `zig build benchmark` passed the recorded regression budgets.
- Linux aarch64 and Windows x86-64 example bundle matrices passed with explicit cross targets.
- `zig build test-dsp-fixture-builds` cross-compiles the fixture runner for Linux aarch64, Linux x86-64, and Windows x86-64. Cross-compilation does not count as native execution.
- Native macOS host lifecycle testing remains a manual check. Native Windows, Linux, X11, Wayland, and CLAP host coverage remains unavailable locally.

## First execution phase

The best next phase is framework work, not neural inference:

- [x] Land configurable mono and stereo bus layouts.
- [x] Land the generic resource job and immutable resource exchange together, because either one without the other encourages unsafe model sharing.
- [x] Build the Resource Swap Probe and run it under sanitizers and repeated component teardown.
- [x] Add bounded SRC and dynamic latency through the Fixed-Rate Processor.
- [x] Add bounded resource references, component-state recovery, and the Model Shell probe.
- [x] Publish and test the downstream C kernel integration recipe.
- [x] Add scoped denormal handling and deterministic silence-tail performance coverage.
- [x] Add a headless C++-to-Zig fixture parity runner with randomized block boundaries.

Completing this phase would make a Zig NAM effort technically credible while also benefiting convolution reverbs, cabinet loaders, spectral processors, wavetable instruments, and any plugin that swaps large prepared DSP resources.
