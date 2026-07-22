# Zig NAM Readiness Plan

## Purpose

Use the Rust Neural Amp Modeler port as a concrete production workload for deciding what `zig-vst3` and `zig-vst3-plugin` need next. This plan does not authorize a NAM rewrite. It identifies reusable prerequisites, keeps model-specific code out of the plugin framework, and defines smaller proving milestones.

The audit used `nam-rs` commit `26cd9412567d397d8af395977732659100d9b26b` on its `main` branch.

## Architectural conclusion

A Zig NAM implementation should have three layers:

1. `zig-vst3` owns VST3 ABI behavior, host negotiation, bus layouts, latency reporting, restart requests, and platform integration.
2. `zig-vst3-plugin` owns safe plugin-authoring patterns: parameters, state, background resource jobs, immutable resource publication, real-time-safe reclamation, resampling, and reusable model-loader UI.
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

These facilities cover most of a basic NAM editor. They do not yet cover safe ownership and execution of a large dynamically loaded model.

### Important gaps

| Capability | Current state | Required home | Priority |
| --- | --- | --- | --- |
| Configurable audio layouts | Mono, stereo, absent, and mixed main-bus layouts are public and validated | `zig-vst3` and `zig-vst3-plugin` | Complete |
| Immutable model publication | Specialized fixed-slot sample and IR stores exist, but no generic large-resource swap | `zig-vst3-plugin` | P0 |
| Deferred destruction | No reusable way to retire a model without freeing it on the audio thread | `zig-vst3-plugin` | P0 |
| Generic background resource jobs | Audio decoding is specialized to WAV and AIFF | `zig-vst3-plugin` | P0 |
| Streaming sample-rate conversion | No bounded, allocation-free, stateful SRC abstraction | Reusable DSP package, surfaced through `zig-vst3-plugin` | P0 |
| Dynamic latency notification | Processor latency queries exist, but model or SRC changes lack a complete public update path | `zig-vst3` and `zig-vst3-plugin` | P0 |
| Resource persistence | Parameter state and small editor text exist, but no generic path identity and missing-file recovery contract | `zig-vst3-plugin` | P0 |
| Consumer C kernel integration | Internal build code compiles C, but package consumers lack a documented helper and reference layout | Package build API and DSP library | P1 |
| CPU dispatch | No portable baseline plus optimized runtime kernel selection contract | DSP library | P1 |
| Denormal policy | No explicit reusable process-thread FTZ/DAZ or equivalent policy | `zig-vst3-plugin` or DSP library | P1 |
| Headless golden rendering | Examples have strong tests, but no reusable model parity runner with WAV fixtures | `zig-nam` tooling | P1 |
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

- [ ] Extract the shared lifecycle from the audio importer: idle, validating, loading, ready, cancellation, failure, retry, and replacement.
- [ ] Make decoding or parsing a caller-supplied worker operation with explicit byte, time, and result limits.
- [ ] Support jobs that begin during component initialization without an open editor.
- [ ] Separate status snapshots from the loaded resource so the GUI never locks the resource owner.
- [ ] Preserve generation checks and reject stale completion callbacks after replacement or teardown.

Exit criteria:

- A test plugin loads a bounded non-audio fixture through drop, picker, and restored state.
- Cancellation and teardown join or reject all pending work without callbacks into destroyed instances.
- The audio thread never performs file access, allocation, logging, or host calls.

### 3. Immutable resource exchange and reclamation

- [ ] Design a single-writer publication primitive for heap-owned immutable resources.
- [ ] Let the audio thread adopt a complete model at a block boundary without a mutex.
- [ ] Return replaced resources to a non-real-time reclaimer without reference-count destruction on the audio thread.
- [ ] Define behavior when publication slots are full, a model is replaced repeatedly, or processing stops during a swap.
- [ ] Make ownership, memory ordering, and maximum outstanding resources explicit in the API.

Exit criteria:

- Generated lifecycle tests cover publish, adopt, replace, cancel, reset, stop, and destroy sequences.
- Thread and address sanitizers pass repeated concurrent publication tests.
- A real-time audit proves process-time operations are bounded and allocation-free.

### 4. Bounded streaming sample-rate conversion

- [ ] Select or build a resampler with known quality, latency, and licensing.
- [ ] Allocate all filter state, queues, and scratch storage during preparation.
- [ ] Handle arbitrary host block sizes without growing storage.
- [ ] Define startup, drain, reset, discontinuity, and sample-rate-change behavior.
- [ ] Report exact round-trip latency and preserve dry/wet alignment where relevant.
- [ ] Benchmark common NAM rate pairs, especially 44.1, 48, 88.2, and 96 kHz.

Exit criteria:

- No process path allocates, locks, or changes capacity.
- Impulse, sine, sweep, and randomized block tests verify latency, continuity, bounded error, and deterministic reset.
- A fixed-rate probe plugin passes variable-block and state-transition validator tests.

### 5. Runtime latency and restart contract

- [ ] Expose a public processor-to-controller request for `kLatencyChanged`.
- [ ] Define when a newly loaded model or SRC configuration becomes active relative to the reported latency.
- [ ] Coalesce redundant restart notifications outside the audio callback.
- [ ] Test hosts that query latency before activation, after preparation, and after resource replacement.

Exit criteria:

- A probe plugin changes between two prepared latency modes without calling the host from processing.
- The host-visible latency and active processing path change in a documented order.
- State restore and repeated activation do not leave stale latency.

### 6. Resource state and recovery

- [ ] Add bounded non-parameter component state for a resource path, stable identity, metadata summary, and schema version.
- [ ] Do not serialize model weights into ordinary plugin state by default.
- [ ] Define missing, moved, changed, and unsupported resource behavior.
- [ ] Reload restored resources asynchronously and keep the plugin safe and silent until publication completes.
- [ ] Provide a relink action and accessible status without requiring the editor to remain open.

Exit criteria:

- State round trips without truncating a valid maximum-length path.
- Missing files restore to a recoverable state instead of failing component initialization.
- A changed file cannot silently reuse metadata from an older model generation.

## P1 reusable infrastructure

### Public C kernel integration

- [ ] Document how a downstream package adds portable C sources, include paths, compile flags, and target-specific objects to a plugin bundle.
- [ ] Provide a small reference kernel with a Zig fallback and C differential tests.
- [ ] Keep `-ffast-math` scoped to explicitly selected kernels. Do not apply it to the whole plugin or model parser.
- [ ] Verify macOS universal, Linux, and Windows builds, including symbol visibility and allocator boundaries.

Zig makes direct C interoperability natural, but integration is only an advantage if downstream builds can use it without copying this repository's internal build functions.

### CPU feature dispatch

- [ ] Define a portable baseline kernel set.
- [ ] Add runtime selection for supported accelerated variants where distribution targets require it.
- [ ] Keep dispatch outside inner loops and make the chosen kernel observable in diagnostics.
- [ ] Compare Zig, portable C, and accelerated C implementations with identical fixtures.

### Denormal handling

- [ ] Decide between scoped processor-thread FTZ/DAZ, numerically safe noise, or architecture-neutral algorithmic avoidance.
- [ ] Restore any modified floating-point environment when required by the host contract.
- [ ] Add silence-tail performance tests for recurrent and convolution workloads.

### Headless DSP fixture runner

- [ ] Define a host-independent block processor test interface.
- [ ] Feed WAV fixtures with fixed and randomized block boundaries.
- [ ] Compare output against C++ reference renders with documented absolute, relative, and aggregate error limits.
- [ ] Record performance by architecture, model, sample format, sample rate, and kernel backend.

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
- A failed model load keeps the last valid model active unless the user explicitly clears it.
- Model replacement becomes visible atomically at a documented block boundary.
- Sample-rate conversion latency is explicit and host-visible.
- Cross-compilation is build coverage, not native host verification.
- CLAP support is a separate backend decision. It should not distort VST3-specific APIs.

## Validation matrix for each prerequisite

- [ ] Deterministic unit and generated lifecycle tests.
- [ ] Real-time audit and allocation checks.
- [ ] Address, undefined-behavior, and thread sanitizers where supported.
- [ ] Raw VST3 ABI checks for any backend change.
- [ ] Steinberg validator in both sample formats.
- [ ] Linux aarch64 and Windows x86_64 cross-target bundles.
- [ ] Native macOS host lifecycle checks when practical.
- [ ] Performance measurements with fixed fixtures and recorded machine context.
- [ ] Documentation of unavailable native Windows, X11, Wayland, and CLAP coverage.

## First execution phase

The best next phase is framework work, not neural inference:

- [x] Land configurable mono and stereo bus layouts.
- [ ] Land the generic resource job and immutable resource exchange together, because either one without the other encourages unsafe model sharing.
- [ ] Build the Resource Swap Probe and run it under sanitizers and repeated editor/component teardown.
- [ ] Add bounded SRC and dynamic latency through the Fixed-Rate Processor.
- [ ] Publish and test the downstream C kernel integration recipe.

Completing this phase would make a Zig NAM effort technically credible while also benefiting convolution reverbs, cabinet loaders, spectral processors, wavetable instruments, and any plugin that swaps large prepared DSP resources.
