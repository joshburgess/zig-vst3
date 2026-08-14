# Stability Policy

This project is pre-1.0. The raw VST3 API has carried a preview compatibility policy since `zig-vst3-0.1.0`. `zig-vst3-0.3.0-rc.1` established the first release-candidate compatibility boundary for the higher-level plugin framework, and stable `zig-vst3-0.3.0` retains it.

Host callback boundaries treat raw pointer arguments as untrusted. Public callback declarations use nullable C pointer types for host-provided buffers, structures, identifiers, events, scalar outputs, and GUI telemetry storage. Implementations reject null before dereference, output mutation, retained-reference changes, or configuration-hook dispatch. Internal hooks continue to receive typed non-null pointers after boundary validation.

Direct processor-runtime calls enforce the same instrumented realtime audit used by format and standalone adapters. After context validation, `process` and `process64` report `RealtimeSafetyViolation` if the processor observes allocation, locking, file access, logging, host calls, or GUI calls inside the realtime scope. Saturated audit nesting and reference-generation exhaustion return checked failures instead of terminating.

The shipped-example source gate inspects every `process` and `process64` callback plus directly named block and sample helpers. It rejects allocation, deallocation, locks, blocking waits, thread operations, file or system access, logging, host callbacks, and GUI calls in those realtime bodies.

## Toolchain

The supported Zig version is the exact version in [docs/toolchain.md](toolchain.md). Toolchain upgrades are breaking work unless the changelog says otherwise. They should land as dedicated changes with the release gate passing on the new compiler.

The pinned VST3 SDK version is also part of the tested surface. SDK upgrades should update the toolchain docs, release notes, ABI checks, and validator expectations together.

The spatial interoperability gate pins libmysofa and libspatialaudio source revisions and archive hashes. Changing either renderer, its build options, the public SOFA fixtures, the declared peak or normalized RMS limits, or the delay and normalization alignment is verification-policy work and requires the focused spatial gate plus the complete release graph.

The Vorbis packet-loss interoperability gate pins libogg 1.3.5 and libvorbis 1.3.7 source archives and hashes. Changing either source, the complete-packet removal contract, the synthetic Xiph overlap blocks, the case geometry, or the peak and normalized RMS limits is verification-policy work and requires the focused Vorbis gate plus the complete release graph.

The second Vorbis decoder gate pins the exact stb_vorbis source revision and hash. Changing that source, its compile definitions, the strict single-link Ogg preflight, explicit chain assembly, case matrix, malformed-input contract, or PCM error limits is verification-policy work and requires the established-decoder gate plus the complete release graph.

The fixed-point Vorbis decoder gate pins the exact Tremor revision, archive hash, license identity, generic C build definitions, and libogg dependency. Changing that source, its integer PCM normalization, strict single-link Ogg preflight, explicit chain assembly, failure injection, case matrix, malformed-input contract, or PCM error limits is verification-policy work and requires the established-decoder gate plus the complete release graph.

## Raw VST3 API

`zig-vst3` mirrors VST3 SDK ABI declarations and provides helper objects for tests and shell integration. ABI declarations are expected to track the SDK closely. When an SDK interface is covered by `zig build raw-api-abi`, changes to layout, calling convention, entry symbols, TUID bytes, or result semantics should be treated as release-blocking unless they are intentional SDK-alignment fixes.

Before `zig-vst3-0.1.0`, helper APIs can still change. After `zig-vst3-0.1.0`, raw ABI declarations and checked helper behavior should change only with clear release notes and passing ABI gates.

Host-facing reference-count helpers contain a saturated increment and a decrement observed at zero without panicking across the C ABI. They leave the counter unchanged and return the maximum count as the invalid-release sentinel. This does not make access through an already destroyed object pointer valid.

ARA audio-reader leases contain a release observed at zero without underflowing the active-reader count. Reader shutdown still waits for every valid concurrent lease before releasing the host reader.

Raw interface queries model the requested identifier and output slot as nullable C pointers. Framework query implementations reject either null argument before comparing identifiers, retaining an interface, or changing caller output.

Framework-owned factory, component, processor, parameter, stream, event, and automation-queue callbacks model host-supplied output buffers and required input structures as nullable C pointers. They reject null before mutation, state transitions, collection append, or realtime dispatch.

Internal conversions from native collection sizes to signed and unsigned host count fields saturate at the target field maximum. The corresponding next-count helpers also contain a maximum native index without integer overflow.

Native audio callbacks reject a null channel-pointer array when the negotiated topology requires channels. A zero-channel direction may still supply null. Native editor callbacks model C buffers as nullable and reject null before producing slices, writing scalar results, or publishing snapshots.

## Plugin Framework

`zig-vst3-plugin` is the plugin framework package. Declarations classified compatibility-ready in the [Framework API Compatibility Inventory](framework/api-compatibility.md) follow the [Framework Compatibility Policy](framework/compatibility-policy.md) through the `0.3.x` line. Experimental declarations and optional platform modules may still change before promotion.

The first structured public-surface review is recorded in [Framework API Compatibility Inventory](framework/api-compatibility.md). LV2, AUv2, ARA product APIs, the supported VSTGUI authoring layer, standalone shells, split-device correction, and optional platform modules remain experimental until their listed external evidence is complete.

Within `0.3.x`, compatibility-ready plugin declarations, reflected parameter metadata, state, automation, events, units, programs, DSP and resource namespaces, standalone runtime primitives, and reusable VST3 shells preserve their documented source contracts. A later pre-1.0 minor release may make breaking changes with the deprecation and migration process in the framework policy.

The installed-package gate compares the current declaration manifest with the frozen `0.3.0-rc.1` candidate baseline. Compatibility-ready module-root declarations cannot disappear or become experimental silently. A later accepted removal requires a complete record naming the deprecation release, a later minor boundary, the last supported release, a direct replacement, and release notes. Independent downstream effect, instrument, and older-consumer projects exercise the same package boundary used by plugin authors.

The standalone split-device correction API is also experimental. `CaptureRateLifecycleConfig` deliberately leaves FIFO targets, correction limits and response, priming thresholds, correction cadence, and recovery policy with the product. Its defaults preserve immediate rendering and silence substitution. Products that opt into rebuffering receive deterministic silence during priming and on the complete underflow block that begins recovery. `reset` is quiescent-only and restores the configured startup state. The policy names, defaults, report fields, callback ownership, stable-address requirements, and reset contract passed the first API review. The repository-owned policy and operating-state enums reserve unknown integer values so later additions are not ABI-exhaustive, while public operations reject unknown values transactionally.

### VSTGUI component API

The reviewed authoring surface is `@import("zig-vst3").vstgui`. Parameter descriptions, standard controls, composition, themes, layouts, meters, graphs, assets, fonts, drawing callbacks, and the `create*View` functions are exercised by the component gallery and production editors. The Parametric EQ and IR Loader independently use the public asset, font, canvas, and drawing callback contracts. Changes to the supported subset should update its consumers and the author guide in the same commit.

Native assistive-technology bridges remain experimental. macOS behavior is integration-tested, Windows support is cross-compiled, and the Linux AT-SPI transport passes an isolated D-Bus fixture in Debug and sanitizer builds. Linux X11 clipboard exchange passes its native fixture, while Wayland data-control exchange passes an isolated protocol fixture plus Linux x86-64 and AArch64 strict compilation. Native VoiceOver, Narrator, Orca, Accerciser, X11, Wayland, and AT-SPI workflows retain the verification limits listed in [VSTGUI Component Authoring](framework/vstgui-components.md#api-status).

## Compatibility Expectations

Every release should state:

- Required Zig version.
- Pinned VST3 SDK version.
- Passing local release gate.
- CI platforms covered.
- Validator coverage.
- Real-host smoke coverage and explicit deferrals.
- Known breaking changes or migration notes.

State compatibility should be preserved when practical. Parameter removals should load older state by ignoring unknown ids. Parameter additions should keep defaults when older state is loaded. Parameter renames should use explicit id migrations.

## Breaking Changes

Breaking changes are acceptable before 1.0, but they should be visible:

- Keep them in dedicated commits or PRs when possible.
- Record them in `CHANGELOG.md`.
- Update the public docs in the same change.
- Keep examples compiling against the new API.

After `zig-vst3-0.1.0`, avoid casual churn in the raw API. Framework churn is still allowed, but it should have a clear reason and migration path.
