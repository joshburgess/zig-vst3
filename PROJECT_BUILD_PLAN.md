# VST3 in Zig: Project Plan

A staged plan for building a VST3 plugin framework in Zig, structured for delegation to coding agents. Each phase has explicit entry conditions, deliverables, exit criteria, and iteration cycles. Tasks are sized to be tractable for an agent working in isolation with the documents and code listed in **Inputs**.

---

## Project Overview

**Goal.** Build a reusable VST3 plugin framework in Zig that lets developers ship audio plugins on Linux, macOS, and Windows. Two layers, mirroring the Rust ecosystem split:

- **Layer 1: `vst3-zig`**: Raw bindings to the VST3 COM API. Hand-translated interface definitions, comptime vtable scaffolding, GUID/TUID handling, factory entry points. Useful on its own.
- **Layer 2: `zig-plug`**: A higher-level framework with a clean `Plugin` interface, parameter system, state save/load, bundler tooling, sample-accurate automation. Builds on Layer 1.

**Targets from day one.** Linux, macOS, Windows on x86_64 and aarch64. The repository should compile on all three platforms from the first CI pipeline. Validator and host-load checks become required only after their harnesses exist.

**Reference projects.**
- `RustAudio/vst3-sys`: first-generation Rust bindings, hand-translated approach
- `coupler-rs/vst3-rs`: second-generation Rust bindings, libclang-generated
- `robbert-vdh/nih-plug`: the framework we're matching at Layer 2
- Steinberg VST3 SDK 3.8.0 or newer, MIT-licensed since 3.8.0

**Pinned versions.**
- Zig: pin an exact compiler version in `docs/toolchain.md` and CI. Update it only through a dedicated PR.
- VST3 SDK: pin an exact tag or commit in `scripts/fetch_sdk.*`, record the SDK version and commit in `docs/toolchain.md`, and verify the downloaded checkout before building tests.
- Hosts used for manual compatibility: record product name, version, OS, CPU architecture, and test date in `docs/host-matrix.md`.
- Generated C++ ABI fixtures: store expected outputs by SDK version and target triple so interface translations are reproducible.

**Non-goals (initially).**
- Hosting plugins (we build plugins, not hosts)
- VST2 compatibility
- A bundled GUI library (we expose the `IPlugView` hook; users plug in their own toolkit)
- Plugin sandboxing or out-of-process hosting

**Current status.** Layer 1 now builds a minimal gain plugin on macOS, emits `.vst3` bundles for macOS, Linux, and Windows, and passes Steinberg's validator locally on macOS with `zig build validate-gain`.

**Total estimated duration.** 6–9 months for a Layer 2 release that's genuinely useful to others. The first Layer 1 gain plugin milestone is complete locally on macOS; the remaining Layer 1 work is hardening the raw API, CI coverage, and host smoke testing.

---

## Working Model for Coding Agents

Each phase is broken into **work units**. A work unit is sized so that one agent can complete it in a single session with clear inputs and outputs. Work units within a phase may be sequential (later ones depend on earlier ones) or parallel (independent).

**Conventions used throughout this document:**

- **Inputs**: files, docs, and prior deliverables the agent must read before starting
- **Deliverables**: concrete artifacts the agent produces (files, tests, docs)
- **Exit criteria**: objective checks that determine whether the work unit is done
- **Iteration cycle**: the loop the agent runs until exit criteria are met

**Standard iteration cycle (applies to every code work unit unless overridden):**

1. Read all listed inputs in full
2. Sketch the design as comments or a brief design note
3. Implement
4. Run unit tests; iterate until green
5. Run integration tests (validator, host load) where applicable
6. Run the validation tier required for the current phase
7. Self-review against exit criteria; document any deviations
8. Open PR with the design note, code, and test output

**Definition of Done for any code work unit:**

- All exit criteria met
- Required CI tier passes on Linux, macOS, and Windows
- Public API has doc comments
- Changes documented in `CHANGELOG.md`
- No new TODOs without an associated tracked issue

**Validation tiers.**
- **Tier 0: Compile and unit tests.** `zig build` and `zig build test` on Linux, macOS, and Windows.
- **Tier 1: ABI tests.** Generated C++ fixture comparisons for TUID bytes, struct sizes, alignments, field offsets, enum values, calling conventions, symbol exports, and vtable order.
- **Tier 2: SDK validator.** Steinberg `validator` runs against a built `.vst3` bundle on each supported OS where the validator is available.
- **Tier 3: Host smoke tests.** Manual or scheduled tests in real hosts. These are release gates, not per-PR gates, unless a host-specific regression is being fixed.

---

## Phase 0: Reconnaissance and Foundations

**Duration.** 1–2 weeks. Single agent or small team; mostly reading and infrastructure setup.

**Goal.** Eliminate unknowns before any VST3 code is written. Stand up the repository, CI, and validator harness so that every later phase has a working test loop from day one.

### Work Unit 0.1: Repository scaffold

**Inputs.** None.

**Deliverables.**
- Monorepo with two top-level crates/packages: `vst3-zig/` and `zig-plug/` (the latter empty for now)
- `build.zig` at root that builds a stub shared library on each target
- `.gitignore`, `LICENSE` (MIT), `README.md` with project status badge
- `CONTRIBUTING.md` describing the work-unit model and PR conventions
- `docs/` directory with `architecture.md` (initially a stub)

**Exit criteria.**
- `zig build` succeeds on Linux, macOS, Windows
- The stub library produces `.so`, `.dylib`, `.dll` outputs respectively
- Cross-compilation from Linux to the other two targets works (`zig build -Dtarget=x86_64-windows`, etc.)

### Work Unit 0.2: CI pipeline

**Inputs.** Work Unit 0.1.

**Deliverables.**
- GitHub Actions workflow that runs on every PR
- Three parallel jobs: ubuntu-latest, macos-latest, windows-latest
- Each job runs `zig build`, `zig build test`, and uploads build artifacts
- A separate cross-compilation job that builds all three targets from Linux
- Cache configuration for Zig's global cache to keep CI fast

**Exit criteria.**
- A trivial PR that adds a no-op test passes CI on all three platforms
- CI run time under 10 minutes for a clean build, under 3 minutes when cached

### Work Unit 0.3: VST3 SDK vendoring and validator harness

**Inputs.** None. This work unit fetches the SDK.

**Deliverables.**
- Script `scripts/fetch_sdk.sh` (and `.ps1`) that clones VST3 SDK 3.8.0+ to a known location, not committed to the repo
- SDK tag or commit pinned in the fetch scripts, with checksum or commit verification
- `build.zig` step that builds the Steinberg `validator` tool from the SDK
- Wrapper script `scripts/validate.sh` that runs the validator against a built `.vst3` bundle and reports pass/fail
- `docs/validator.md` documenting how to use the harness locally and what each validator check means
- `docs/toolchain.md` documenting the Zig version, SDK version, SDK commit, and local cache path

**Exit criteria.**
- A team member can run `scripts/validate.sh path/to/Plugin.vst3` and get a clean pass/fail with detailed output
- The validator runs in CI as a job (initially testing against a downloaded reference plugin, e.g. the SDK's `again` example, to confirm the harness works)
- CI fails if the fetched SDK commit differs from the pinned commit

### Work Unit 0.4: Reference plugin walkthrough

**Inputs.** Work Units 0.1-0.3. The `coupler-rs/vst3-rs` repo at a pinned tag. The `RustAudio/vst3-sys` repo at a pinned tag.

**Deliverables.**
- A document `docs/reference-walkthrough.md` covering:
  - How `coupler-rs/vst3` generates its bindings, with examples of the generated output
  - How `vst3-sys` declares interfaces via `com-rs` macros, with examples
  - A trace of what happens when a host loads a plugin: `GetPluginFactory` -> `IPluginFactory::createInstance` -> `IPluginBase::initialize` -> `IComponent::setActive` -> `IAudioProcessor::process`
  - Specific design choices each project made and which we should consider adopting, modifying, or rejecting for the Zig port
- The agent must build and load `coupler-rs/vst3`'s gain example in at least one host (Reaper recommended) and capture a debugger trace of the first 50 calls into the plugin
- `docs/toolchain.md` records the exact reference-project tags used for the walkthrough

**Exit criteria.**
- Document is reviewed and merged
- Trace log committed to `docs/traces/` for future reference
- Open questions captured as GitHub issues with the `phase-1-design` label

### Work Unit 0.5: VST3 SDK header inventory

**Inputs.** Work Unit 0.3.

**Deliverables.**
- A spreadsheet or markdown table at `docs/interface-inventory.md` listing every interface in `pluginterfaces/base/` and `pluginterfaces/vst/`, with:
  - Interface name
  - File path in SDK
  - TUID
  - Inheritance chain
  - Whether it's host-side, plugin-side, or both
  - Priority for our project: P0 (must-have for gain plugin), P1 (must-have for typical effects/synths), P2 (advanced features), P3 (rarely used)

**Exit criteria.**
- Every interface in the pinned SDK's plugin-facing headers is categorized, including VST3 3.8.0 additions such as `IMidiLearn2`, `IMidiMapping2`, `IWaylandHost`, and `IWaylandFrame`
- P0 list contains roughly: `FUnknown`, `IPluginBase`, `IPluginFactory`/`2`/`3`, `IComponent`, `IAudioProcessor`, `IEditController`, `IBStream`, `IParameterChanges`, `IParamValueQueue`, `IEventList`, `IConnectionPoint`, `IHostApplication`
- P1/P2/P3 priorities explicitly cover MIDI 2.0 and Linux Wayland interfaces added in SDK 3.8.0
- The inventory is the canonical source of truth for Phase 2's translation work

---

## Phase 1: COM/Vtable Foundation

**Status.** Substantially complete for the first plugin milestone. The raw layer has enough COM, factory, component, controller, audio processor, bundle, and validator support to ship a minimal gain plugin through Steinberg's validator on macOS.

**Duration.** 2–3 weeks originally planned. The phase expanded to include the first real VST3 bundle and validator pass.

**Goal.** Build the machinery needed for ABI-compatible COM objects and prove it against a real VST3 plugin. This phase now exits when the gain plugin validates and the remaining raw-layer hardening work is tracked separately.

**Current exit status.**
- `zig build test` passes locally.
- `zig build validate-gain` passes locally on macOS.
- `zig build phase1` runs the gain validator path on macOS.
- `bundle-gain`, `bundle-gain-linux`, and `bundle-gain-windows` produce platform bundle layouts.

**Remaining hardening before Layer 2 should depend on this API.**
- Add CI jobs for validator and cross-target bundle checks where the platform supports them.
- Replace one-off plugin object wiring with reusable raw-layer helpers for interface maps and allocator-owned objects.
- Record real DAW smoke test results under `docs/host-matrix.md`.
- Keep build steps aligned with the gain plugin naming now that the scaffold-era stub artifact has been retired.

### Work Unit 1.1: TUID/FUID handling

**Inputs.** Phase 0 deliverables. `pluginterfaces/base/funknown.h`, `falignpush.h`, `falignpop.h`, `fstrdefs.h`, `ftypes.h` from the SDK.

**Deliverables.**
- `vst3-zig/src/tuid.zig` with:
  - `TUID` type (16-byte array)
  - `FUID` type with `equals`, `from_tuid`, `to_tuid`, `from_string`, `to_string` methods
  - `inline_uid` comptime function matching the C++ `INLINE_UID` macro semantics, with correct platform-conditional byte ordering (Windows COM-style vs. Itanium)
  - `inline_uid_from_string` for the string-form initializer
- Tests verifying byte layout matches what the C++ headers produce on each platform: for at least 5 well-known TUIDs (`FUnknown::iid`, `IPluginBase::iid`, `IComponent::iid`, `IAudioProcessor::iid`, `IEditController::iid`)
- Documentation in `docs/tuid.md` explaining the platform differences and why they exist

**Exit criteria.**
- Test suite includes a comparison: build a tiny C++ program with the SDK that prints the bytes of each test TUID, build a Zig program that prints the bytes of the same TUIDs, diff the outputs: must be byte-identical on all three platforms
- All TUID tests pass on Linux, macOS, Windows
- The C++ fixture output is checked in under `tests/fixtures/abi/<sdk-version>/<target-triple>/`

### Work Unit 1.2: Vtable scaffolding design

**Inputs.** Work Unit 1.1. The reference walkthrough from Work Unit 0.4. The `com-rs` source from `vst3-sys`.

**Deliverables.**
- A design document `docs/vtable-design.md` covering at least three candidate approaches:
  1. Declarative interface description as a comptime struct, with comptime reflection generating vtables
  2. Interface as a Zig type with declared method signatures, framework derives vtable layout
  3. Hybrid: explicit vtable struct definitions, comptime helper to wire them up to user methods
- For each approach: pros, cons, ergonomics example, ABI risks
- Recommendation with reasoning
- A prototype implementation of the chosen approach, sufficient to declare a single interface (`FUnknown`) and implement it on a test struct

**Exit criteria.**
- Design doc reviewed and approved before implementation begins
- Prototype compiles on all three platforms
- A test exists that calls `queryInterface(FUnknown::iid)` on the test struct and gets back a valid pointer with the correct vtable

### Work Unit 1.3: Reference counting

**Inputs.** Work Units 1.1, 1.2.

**Deliverables.**
- Atomic refcount implementation in the chosen vtable scaffolding
- `addRef` returns new count, `release` decrements and destroys at zero
- Allocator integration: objects created via the framework own their allocator and use it for their final destruction
- Tests for: single ref, multiple refs, double-release (must be detected in debug builds), thread-safety stress test

**Exit criteria.**
- `zig build test` includes a stress test that hammers `addRef`/`release` from 8 threads for 1 second with no leaks or double-frees (verified under tsan or valgrind on Linux)
- Debug builds catch double-release with a panic; release builds match VST3 SDK behavior (undefined but typically silent)

### Work Unit 1.4: Multi-interface objects

**Inputs.** Work Units 1.1–1.3.

**Deliverables.**
- Extension of the vtable scaffolding to support a single object implementing multiple interfaces
- Correct handling of `queryInterface` returning different vtable pointers for different IIDs, all referring to the same logical object
- Pointer fixup math: when host calls `queryInterface` for `IAudioProcessor`, the returned pointer must be such that `(*returned_ptr)->process(returned_ptr, ...)` correctly dispatches to the user's implementation
- Tests with a synthetic 3-interface object exercising all combinations of `queryInterface` calls

**Exit criteria.**
- A test "fake host" function takes an `FUnknown*`, queries for each of three interfaces, calls a method on each, and verifies all three calls reach the same underlying Zig struct with the correct state
- Same test runs on all three platforms with identical results

### Work Unit 1.5: Phase 1 integration milestone

**Inputs.** Work Units 1.1–1.4.

**Deliverables.**
- An end-to-end test that exercises the COM machinery without any VST3 specifics:
  - Three test interfaces (`ITestA`, `ITestB`, `ITestC`) defined using the framework
  - A `TestObject` Zig struct that implements all three
  - A C test harness (built alongside Zig tests) that loads the test object via a factory, calls methods on each interface via the C ABI, and verifies behavior
- The C harness specifically tests the ABI from the C++ side, since that's what real hosts will do

**Exit criteria.**
- C harness passes on Linux (g++ and clang++), macOS (clang++), Windows (MSVC and clang-cl)
- No memory leaks under valgrind/asan
- Phase 1 retrospective document in `docs/retrospectives/phase-1.md` capturing what was harder than expected, what's still uncertain, and any follow-up tasks
- Tier 1 ABI tests pass for every synthetic interface used in Phase 1

---

## Phase 2: VST3 Interface Translations

**Duration.** 3–4 weeks. Mechanical but voluminous; parallelizable across multiple agents.

**Goal.** Translate every P0 and P1 interface from the inventory into Zig, with TUID constants, vtable layouts, and round-trip ABI tests.

### Work Unit Pattern (repeated per interface group)

Each interface or small group of related interfaces becomes its own work unit, following this template:

**Inputs.** Phase 1 deliverables. The relevant SDK header(s). The interface inventory entry.

**Deliverables.**
- Zig translation in `vst3-zig/src/pluginterfaces/<group>/<interface>.zig`
- TUID constant matching the SDK byte-for-byte
- Vtable struct with all methods in declaration order
- Any associated structs, enums, and constants from the same header
- Doc comments on every public type and method, copied/adapted from the SDK comments
- Round-trip test: a Zig implementation, called from C, exercising every method
- ABI fixture test generated from C++ for every translated public type:
  - `sizeof`
  - `alignof`
  - field offsets
  - enum and bitflag values
  - calling convention and return type checks
  - vtable method order
- Entry in `CHANGELOG.md` listing what was added

**Exit criteria.**
- C harness round-trip test passes on all three platforms
- Tier 1 ABI fixture tests pass on all three platforms
- Public API has doc comments
- No `TODO` or `FIXME` markers without a tracked issue

### Work Unit 2.1: `FUnknown` and `IPluginBase`

The base of everything. Should be largely already done from Phase 1; this work unit formalizes and ships it.

### Work Unit 2.2: `IPluginFactory`, `IPluginFactory2`, `IPluginFactory3`

Plugin discovery and instantiation. Includes `PFactoryInfo`, `PClassInfo`, `PClassInfo2`, `PClassInfoW`.

### Work Unit 2.3: `IBStream`, `ISizeableStream`

State serialization streams.

### Work Unit 2.4: `IComponent` and supporting types

Includes `BusInfo`, `RoutingInfo`, `BusDirection`, `BusType`, `IoMode`.

### Work Unit 2.5: `IAudioProcessor` and process data structures

Includes `ProcessData`, `ProcessSetup`, `ProcessContext`, `AudioBusBuffers`, `SymbolicSampleSizes`, `ProcessModes`. The most performance-critical interface.

### Work Unit 2.6: `IEditController`, `IEditController2`

Includes `ParameterInfo`, `ParameterFlags`, `KnobMode`.

### Work Unit 2.7: Parameter changes and events

`IParameterChanges`, `IParamValueQueue`, `IEventList`, `Event` and all event subtypes (`NoteOnEvent`, `NoteOffEvent`, `DataEvent`, `PolyPressureEvent`, `ChordEvent`, `ScaleEvent`, `LegacyMIDICCOutEvent`, `NoteExpressionValueEvent`, `NoteExpressionTextEvent`).

### Work Unit 2.7a: MIDI 2.0 mapping interfaces

`IMidiLearn2`, `IMidiMapping2`, and related ControllerNumbers additions from SDK 3.8.0. These can be P1 or P2 depending on the inventory, but they must be explicitly categorized so the project does not silently ship stale 3.7-era bindings.

### Work Unit 2.8: Component handler and host application

`IComponentHandler`, `IComponentHandler2`, `IComponentHandler3`, `IHostApplication`, `IConnectionPoint`, `IMessage`, `IAttributeList`.

### Work Unit 2.9: Plug view (no GUI implementation yet)

`IPlugView`, `IPlugFrame`, `IPlugViewContentScaleSupport`, `ViewRect`, platform-specific `kPlatformType*` constants.

### Work Unit 2.9a: Linux Wayland plug view interfaces

`IWaylandHost`, `IWaylandFrame`, and `kPlatformTypeWaylandSurfaceID` from SDK 3.8.0. Treat these as P2 initially unless the inventory finds they are required for current Linux hosts.

### Work Unit 2.10: Unit info and program lists

`IUnitInfo`, `IProgramListData`, `IUnitData`, `UnitInfo`, `ProgramListInfo`. Lower priority; can defer if time runs short.

### Work Unit 2.11: Phase 2 integration milestone

**Inputs.** All previous Phase 2 work units.

**Deliverables.**
- A "kitchen sink" test object that implements every P0 and P1 interface
- Validator runs against a stub plugin built with these bindings. The plugin does not have to do anything useful; it just has to be structurally valid VST3.
- Coverage report: percentage of P0 and P1 interfaces translated and tested

**Exit criteria.**
- Validator's structural checks all pass
- 100% of P0 interfaces translated
- At least 80% of P1 interfaces translated; remainder tracked for later

---

## Phase 3: Build System and Bundling

**Duration.** 1–2 weeks. Can run in parallel with the tail end of Phase 2.

**Goal.** A `build.zig` library and CLI tool that takes a Zig package describing a VST3 plugin and produces correctly-bundled output for all three platforms, including cross-compilation.

### Work Unit 3.1: Module entry points

**Inputs.** Phase 2 deliverables.

**Deliverables.**
- `vst3-zig/src/entry.zig` with platform-conditional exports:
  - Linux: `ModuleEntry`, `ModuleExit`, `GetPluginFactory`
  - macOS: `bundleEntry`, `bundleExit`, `GetPluginFactory`
  - Windows: `InitDll`, `ExitDll`, `GetPluginFactory`
- Comptime helper that takes a user-defined factory and produces the correct exports for the target platform
- Tests that verify the symbols are present in the built shared library on each platform (`nm`, `dumpbin`, etc.)

**Exit criteria.**
- A trivial plugin builds with all required symbols on all three platforms
- The validator can load the plugin and enumerate its (empty) factory

### Work Unit 3.2: macOS bundle generation

**Inputs.** Work Unit 3.1.

**Deliverables.**
- `build.zig` step that produces a proper `.vst3` bundle on macOS
- Generates `Contents/Info.plist` with bundle ID, version, executable name from user-supplied metadata
- Generates `Contents/PkgInfo`
- Places the dylib at `Contents/MacOS/<name>`
- Hooks for code-signing (the actual signing runs outside; the build produces sign-able output)
- Universal binary support (x86_64 + aarch64 in a single bundle)

**Exit criteria.**
- A built bundle passes `codesign --verify --strict --verbose=4` after signing with a developer cert
- Tier 2 validator passes on macOS
- At least one recorded Tier 3 host smoke test loads the bundle correctly

### Work Unit 3.3: Linux bundle generation

**Inputs.** Work Unit 3.1.

**Deliverables.**
- `build.zig` step producing `Plugin.vst3/Contents/x86_64-linux/Plugin.so` (and `aarch64-linux` variant)
- Optional `moduleinfo.json` generation per the VST3 module info spec

**Exit criteria.**
- Tier 2 validator passes on Linux
- At least one recorded Tier 3 Linux host smoke test loads the bundle correctly

### Work Unit 3.4: Windows bundle generation

**Inputs.** Work Unit 3.1.

**Deliverables.**
- `build.zig` step producing `Plugin.vst3/Contents/x86_64-win/Plugin.vst3` (yes, the inner file ends in `.vst3` too: it's a renamed DLL)
- Optional support for monolithic `.vst3` files (single file, no bundle directory) per the VST3 spec
- Cross-compilation from Linux to Windows must work

**Exit criteria.**
- Tier 2 validator passes on Windows
- At least one recorded Tier 3 Windows host smoke test loads the plugin

### Work Unit 3.5: Bundler CLI

**Inputs.** Work Units 3.1–3.4.

**Deliverables.**
- A standalone binary `vst3-bundle` (or a `zig build bundle` step) that takes a built shared library and a metadata file (TOML or JSON: bundle ID, version, vendor, etc.) and produces the platform-correct bundle
- `--target` flag for explicit cross-compilation
- `--universal` flag for macOS universal binaries
- Documentation in `docs/bundling.md` with examples

**Exit criteria.**
- A user can run `zig build bundle -Dtarget=aarch64-macos` from Linux and get a working macOS arm64 bundle
- The bundler is invoked automatically by the standard `zig build` target for plugin packages
- Cross-compiled bundles are marked as build artifacts until validated on their target OS

---

## Phase 4: Layer 1 Reference Plugin

**Duration.** 1 week. The proof that everything below works.

**Goal.** Ship a working gain plugin built directly on Layer 1 (no Layer 2 framework yet). It must pass the validator and load in real hosts on all three platforms.

### Work Unit 4.1: Gain plugin implementation

**Inputs.** Phases 1–3.

**Deliverables.**
- `examples/gain/` directory with a complete VST3 gain plugin
- Implements `IComponent`, `IAudioProcessor`, `IEditController`, `IConnectionPoint`
- One parameter: gain (0.0 to 1.0, mapped to -inf to 0 dB)
- Stereo in, stereo out
- Clean state save/restore
- No GUI (host-provided generic editor)

**Exit criteria.**
- Validator passes with zero warnings on all three platforms
- Plugin loads, processes audio correctly, and persists state in:
  - Reaper (all three platforms)
  - Bitwig Studio (Linux + macOS minimum)
  - Cubase or Studio One (Windows; access permitting)
- A regression test in CI that runs the validator against the built plugin
- `docs/host-matrix.md` records host version, OS, CPU architecture, plugin build hash, and result for each Tier 3 smoke test

### Work Unit 4.2: Layer 1 documentation

**Inputs.** Work Unit 4.1.

**Deliverables.**
- `docs/layer1-tutorial.md` walking through the gain plugin step by step
- API reference generated from doc comments (using `zig build docs`)
- Migration guide for users coming from `vst3-sys` or `coupler-rs/vst3`

**Exit criteria.**
- A developer unfamiliar with the project can follow the tutorial and produce a working plugin
- API reference is published (GitHub Pages or similar)

### Work Unit 4.3: Layer 1 release

**Inputs.** Work Units 4.1, 4.2.

**Deliverables.**
- Tag `vst3-zig-0.1.0` on the repo
- Release notes covering scope, known limitations, and roadmap
- Announcement post draft for r/audioprogramming, KVR, and the Zig community Discord

**Exit criteria.**
- Release published
- At least one external developer has built and run the gain example successfully

---

## Phase 5: Layer 2 Framework Design

**Duration.** 2–3 weeks of design, then ongoing implementation.

**Goal.** Design and prototype the user-facing framework. This is where Zig idioms matter most. Exit this phase with a `Plugin` interface that's pleasant to implement and a parameter system that scales.

**Current status.** The first prototype exists under `zig-plug/src/` and is also exposed as the pure `zig-plug-core` module for Layer 1 integration. The gain plugin uses `PluginSpec` for factory metadata, controller parameter metadata, string conversion, normalized/plain conversion, default parameter state, host automation collection, state serialization, and process context construction. The remaining Phase 5 work is to generalize the remaining gain-specific audio bridge into reusable component/controller glue, then add more examples.

### Work Unit 5.1: Plugin trait equivalent

**Inputs.** Phases 1–4. NIH-plug's `Plugin` trait source.

**Deliverables.**
- Design document `docs/layer2/plugin-interface.md` covering:
  - How a user declares their plugin (struct with declared methods? comptime-introspected fields? explicit registration?)
  - Lifecycle: init, prepare, process, deinit
  - Allocator passing convention
  - Real-time safety: how the API keeps allocation, locks, logging, and unbounded work out of `process`
  - Debug instrumentation for detecting allocator use and lock acquisition on the audio thread
- Prototype in `zig-plug/src/plugin.zig` sufficient to express a gain plugin in 30 lines or fewer

**Exit criteria.**
- Three external Zig developers review the design and at least two find the API natural
- Prototype gain plugin compiles, runs, and passes Steinberg's validator using Layer 1 underneath

### Work Unit 5.2: Parameter system

**Inputs.** Work Unit 5.1. NIH-plug's `Params` derive macro.

**Deliverables.**
- Design document `docs/layer2/parameters.md`
- Implementation supporting: float, int, bool, enum parameters; min/max/default; value-to-string and string-to-value; smoothing (linear, logarithmic, exponential); modulation
- Comptime-reflected parameter struct (analogous to NIH-plug's `Params` derive) so users declare parameters as struct fields
- Tests covering parameter range edge cases, string round-trips, and atomic update from the audio thread

**Exit criteria.**
- Gain plugin's parameter declaration is one struct definition, no boilerplate beyond field annotations
- Parameter automation is routed through the Layer 2 parameter-change view; Reaper and Bitwig smoke tests still need to be recorded

### Work Unit 5.3: State serialization

**Inputs.** Work Unit 5.2.

**Deliverables.**
- Design document `docs/layer2/state.md`
- Implementation that serializes the parameter struct to a binary format suitable for `IBStream`
- Optional: human-readable JSON variant for debugging
- Backward-compatibility story: how do users migrate state when they add/remove parameters?

**Exit criteria.**
- Save and reload of plugin state in a host preserves all parameter values exactly
- Adding a new parameter to a plugin does not break loading of older states

### Work Unit 5.4: Sample-accurate automation

**Inputs.** Work Unit 5.2.

**Deliverables.**
- Implementation of sample-accurate parameter changes per the VST3 `IParameterChanges` model
- Block splitting: when parameter changes occur mid-buffer, the framework either delivers per-sample updates or splits the block at change boundaries (configurable)
- Tests with synthetic automation curves verifying sample-accurate behavior
- Tests that verify no allocation occurs while processing automation in the audio callback

**Exit criteria.**
- An automated parameter sweep in Bitwig produces a correctly sample-accurate output (verified by recording the plugin's output and comparing to the automation curve)

### Work Unit 5.5: MIDI and note expression

**Inputs.** Phase 2's event list translation.

**Deliverables.**
- High-level event types in the framework: `NoteOn`, `NoteOff`, `MidiCC`, `PitchBend`, `Aftertouch`, `NoteExpression`
- Event iterator API for plugins to consume
- SysEx send/receive
- A simple MIDI-effect example plugin (`examples/midi-monitor/`) that prints incoming events

**Exit criteria.**
- A synth example plugin (added in this work unit) responds correctly to keyboard input across all three platforms

### Work Unit 5.6: Reference plugins on Layer 2

**Inputs.** Work Units 5.1–5.5.

**Deliverables.**
- `examples/gain/` rewritten on Layer 2 (10–30 lines)
- `examples/synth/`: simple monophonic synthesizer
- `examples/midi-arp/`: MIDI arpeggiator (effect that consumes and produces MIDI)
- Each example has its own README

**Exit criteria.**
- All three examples pass the validator and load in target hosts
- Each example demonstrates a distinct framework feature

---

## Phase 6: Hardening, Documentation, and 1.0

**Duration.** Ongoing; nominal 4–6 weeks of focused work for the 1.0 milestone.

**Goal.** Take the framework from "works for the example plugins" to "ready for external developers to ship plugins with."

### Work Unit 6.1: Test coverage expansion

**Deliverables.**
- Property-based tests for the COM layer using a Zig property-testing library (or rolled in-house if needed)
- Fuzzing of `IBStream` deserialization
- Stress test: 1000 plugins instantiated and destroyed in a loop with no leaks
- Coverage report; target >80% line coverage on Layer 1, >70% on Layer 2

### Work Unit 6.2: Documentation site

**Deliverables.**
- Documentation site (mdBook, Hugo, or similar) at a stable URL
- Sections: getting started, tutorial, architecture, API reference, FAQ, recipes
- "Recipes" cover common patterns: smoothed parameters, oversampling, latency reporting, side-chain inputs, multi-bus plugins, etc.

### Work Unit 6.3: API stability commitments

**Deliverables.**
- A documented API stability policy in `docs/stability.md`
- Semantic versioning commitments for the 1.x line
- A list of explicitly unstable / experimental APIs marked as such in code
- Migration guides for any pre-1.0 breaking changes

### Work Unit 6.4: Performance benchmarks

**Deliverables.**
- Benchmark suite measuring: per-block overhead vs. raw Layer 1, parameter update overhead, state save/restore time
- Comparison against equivalent NIH-plug builds where possible
- Performance regression tests in CI (fail if any benchmark regresses by >10%)

### Work Unit 6.5: 1.0 release

**Deliverables.**
- All P0 and P1 interfaces translated and tested
- All examples up to date
- Documentation site live
- Tagged release with comprehensive notes
- At least three external developers have shipped plugins built with the framework (a soft criterion but worth tracking)

---

## Cross-Cutting Concerns

### Risk Register

Maintained in `docs/risks.md` and reviewed at each phase boundary. Initial entries:

- **Vtable ABI bug discovered late.** Mitigation: C round-trip tests from Phase 1 onward.
- **Steinberg license interpretation.** Mitigation: stick to MIT-licensed SDK 3.8.0+; do not vendor proprietary headers.
- **Single-maintainer burnout on Layer 2.** Mitigation: design Layer 1 to be useful standalone so the project has value even if Layer 2 stalls.
- **Zig language churn breaking the project.** Mitigation: pin to a specific Zig version per release; document the supported version explicitly.
- **Host-specific bugs not caught by validator.** Mitigation: weekly manual testing rotation across Reaper, Bitwig, Cubase, Ableton, Studio One.
- **Manual host tests become stale.** Mitigation: keep `docs/host-matrix.md` current and require fresh Tier 3 results for releases.

### Coding Standards

- Zig style: follow `zig fmt` defaults; no exceptions
- Naming: types `PascalCase`, functions and variables `snake_case`, constants `SCREAMING_SNAKE_CASE`, file names `snake_case.zig`
- Errors: every fallible operation returns an error union; no silent failures
- Allocation: every API that allocates takes an explicit allocator
- Real-time code path: covered by an explicit audit checklist; debug builds should detect allocation, lock acquisition, logging, and unbounded work where practical
- No `unreachable` in production code paths without a justifying comment

### Documentation Standards

- Every public type and function has a doc comment
- Every interface translation cites the SDK source file and version
- Every architectural decision is captured in an ADR (Architecture Decision Record) under `docs/adr/`

### Review Checklist (use for every PR)

- [ ] Builds on all three platforms
- [ ] Tests pass on all three platforms
- [ ] Validator passes (if applicable)
- [ ] Public API documented
- [ ] CHANGELOG updated
- [ ] No new TODOs without tracked issues
- [ ] Real-time safety reviewed for any code in the audio path
- [ ] Audio-path tests or instrumentation cover allocation and locking where practical
- [ ] Allocator passing convention followed
- [ ] No regressions in benchmarks (Phase 6 onward)

---

## Milestones at a Glance

| Phase | Duration | Exit milestone |
|-------|----------|---------------|
| 0 | 1–2 weeks | CI green on three platforms; validator harness running |
| 1 | 2–3 weeks | Multi-interface COM object round-trips through C harness |
| 2 | 3–4 weeks | All P0 interfaces translated; stub plugin passes validator structurally |
| 3 | 1–2 weeks | Plugin bundles correctly on all three platforms via `zig build` |
| 4 | 1 week | Gain plugin loads in Reaper/Bitwig on all platforms; Layer 1 v0.1.0 released |
| 5 | 4–6 weeks | Three Layer 2 example plugins shipping; framework prototype usable |
| 6 | 4–6 weeks | 1.0 release with documentation, stability commitments, external users |

**Total nominal duration: 16–26 weeks of focused work.** Real elapsed time will be longer; pad estimates by 50% for any single-developer schedule.
