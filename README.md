# zig-vst3

[![CI](https://github.com/joshburgess/zig-vst3/actions/workflows/ci.yml/badge.svg)](https://github.com/joshburgess/zig-vst3/actions/workflows/ci.yml)

Zig libraries for building VST3 audio plugins, with LV2 core, toolkit-neutral UI, and VSTGUI parameter UI adapters.

This repository has two packages:

- `zig-vst3`: raw Zig bindings and helper objects for the VST3 COM API.
- `zig-vst3-plugin`: a higher-level framework for writing plugins with reflected parameters, state, automation, events, and reusable VST3 shells.

The project currently builds and validates example VST3 bundles for effects, analyzers, event processors, and a MIDI-driven synth. The first preview release, `zig-vst3-0.1.0`, is tagged, and the core path is covered by unit tests, ABI checks, Steinberg validator runs, and CI on Linux, macOS, and Windows. The API is still early and may change before a public compatibility promise.

## Which Package Should I Use?

Use `zig-vst3-plugin` if you want to write an audio plugin:

- Declare parameters as Zig struct fields.
- Read and write typed parameter values in your processor.
- Use sample-accurate automation, input events, output events, state save/load, and unit/program metadata without hand-writing VST3 COM plumbing.
- Declare static or bounded live audio topology with one main bus and a compile-time capacity of zero through 254 auxiliary buses per direction. Eight remains the default. Negotiate mono, stereo variants, cinematic and music surround through 7.1, immersive 5.x and 7.x layouts, and first- through seventh-order ambisonics. Publish changes safely to processing, persist topology with backward-compatible state, and coalesce host I/O restarts. Typed host requests cover component reload, I/O, parameter values and titles, latency, MIDI controller assignments, note expression, I/O titles, prefetch support, routing, keyswitches, and parameter ID mapping. The high-level VST3 adapter also forwards optional resource paths, decoded-audio imports, scalar, graph, and text telemetry, and editor-open and editor-close notifications.
- Run the same processor in checked offline renders, realtime standalone callbacks, or VST3. The standalone boundary covers f32 and f64 audio devices, allocation-free routing between physical channels and static main or auxiliary buses, timestamped MIDI 1 and complete UMP input and output with bounded sample-accurate scheduling, transport, deterministic failure silence, transactional device lifecycle, bounded multi-source failure-triggered recovery, and a bounded Steinberg run-loop driver for VSTGUI on Linux. Optional modules provide macOS CoreAudio, CoreMIDI, and Cocoa windows, Windows WASAPI, WinMM, and Win32 windows, and Linux ALSA PCM, RawMIDI, and runtime-loaded X11 and Wayland windows. A shared VST3 bridge supplies the standalone Wayland host, frame, native objects, resize path, and delegated run loop.
- Export the same static f32 processor as an LV2 audio, control, and bounded Atom Sequence plugin with typed MIDI channel events, preserved raw MIDI and non-MIDI Atom bodies, segmented sample-offset time Position transport, host-provided block-size bounds, declaration-driven freewheeling mode, latency reporting, portable parameter-state persistence, optional bounded worker scheduling, discoverable factory presets, a toolkit-neutral native-parent UI bridge, and an optional linked VSTGUI parameter editor.
- Build an ARA 2 document-controller and plugin-extension layer from the pinned official headers, including fixed-capacity factories and object graphs, VST3 companion interfaces, concurrent non-realtime host audio readers, validated analysis requests, licensing queries, host notifications, and host-selectable processing algorithms, typed content readers, backward-compatible filtered archive persistence with bounded product extension state, bounded playback and editor assignments, editor-view state, transactional whole-source or LRU-paged immutable source caches, bounded polyphonic note detection, general and low-register monophonic equal-temperament tuning detection, streamed constant and piecewise variable-tempo detection, bounded constant and changing meter, major or minor key-signature detection, sheet-chord detection, persisted algorithm choice, approved tuning edits, bounded f32 or f64 spectral transforms with immutable playback publication and paged-cache fallback, realtime-safe render-plan publication, cached playback with linear, Catmull-Rom cubic, or eight-tap windowed-sinc interpolation, main-factory registration, compile-time class-list assembly, canonical audio-component aggregation, and a validated dual-precision stereo playback reference product.
- Parse and write bounded Standard MIDI Files without allocation.
- Detect constant and changing 2/4, 3/4, 4/4, 5/4, 6/8, 7/8, 9/8, and 12/8 meter from ARA source onsets and tempo maps. Detection selects the first downbeat, confirms changes across bounded bar windows, and publishes only whole-prior-bar-aligned signature events.
- Detect constant and changing major or natural-minor keys from bounded ARA note content and tempo maps. Weighted pitch-class profiles distinguish all 24 keys, require configurable confidence and runner-up margins, confirm sustained changes, preserve enharmonic circle-of-fifths spelling, and publish official quarter-positioned key-signature events.
- Detect bounded ARA sheet chords from note and tempo content. The detector recognizes major, minor, diminished, augmented, suspended, dominant seventh, major seventh, minor seventh, half-diminished, diminished seventh, minor-major seventh, sixth, added-ninth, ninth, eleventh, thirteenth, and power-chord structures, preserves inversions, filters short transient note artifacts, and confirms changes before publishing official chord events. Sustained gaps produce the official all-unused undefined-chord event.
- Model synchronized MPE zones, expressive note state, sustain, tracking modes, and deterministic member-channel allocation.
- Generate basic waveforms, advance wrapped phase, pan and mix signals, track peak or RMS envelopes, linearly or multiplicatively smooth parameters, ramp gain and positive values, apply bias, waveshaping, chorus, flanging, vibrato, phasing, tempo-synchronized and smoothed modulation, stereo modulation with fixed LFO phase offsets, ladder and topology-preserving filtering, design order 1 through 16 Butterworth, Chebyshev Type I or II, and elliptic cascades, derive all four families from passband and stopband constraints, design weighted least-squares, equiripple, bounded polyphase FIR, and half-band polyphase all-pass IIR filters, split crossovers, apply algorithmic reverb, compression, gating, sample-peak, lookahead, inter-sample, and phase-compensated two- through eight-band dynamics, use FFT, windowing, checked scalar and SIMD Padé fast math, target-native and complex SIMD registers, dispatched copy, gain, affine, add, pointwise multiply, fast math, weighted mix, and stereo layout buffer kernels, Bessel I0, complete elliptic integrals, and real or complex Jacobian elliptic functions, publish bounded mutable snapshots or retained immutable generations to realtime readers, process FIR filters, use lookup tables, fixed matrices and polynomials, scalar processor chains, independent or shared-state duplication, bounded multichannel blocks and process contexts, and bounded multichannel FIR and polyphase IIR oversampling from 2x through 16x, use fractional delays, run partitioned convolution, quantize signed PCM with deterministic direct, TPDF, or noise-shaped conversion, read file-backed WAV, AIFF, uncompressed AIFC, RF64, and Wave64, and write caller-buffer or file-backed PCM16, PCM24, PCM32, or IEEE f32 WAV and AIFF plus 64-bit RF64 and Wave64 streams. Every file-backed integer PCM writer supports transactional dithered append, counted positional I/O injection, short-write retry, padding restoration, and recoverable failure state. WAV and RF64 streams support RIFF INFO, Broadcast Wave `bext`, iXML, and aXML metadata. Wave64 streams support the registered BEXT and LIST/INFO GUID chunks. AIFF streams support standard text chunks. Native FLAC supports bounded encoding, decoding, metadata, seek tables, range reads, and incremental files. Ogg and Vorbis support bounded chained transport, incremental file-backed packet writing with rollback recovery, generated identification, comment, canonical setup, and setup-driven audio packets, scale-aware PCM transient analysis, one-block lookahead, retained short/long mode and continuous center planning, zero-padded stream-boundary extraction, transactional multichannel windowed MDCT, Bark-spaced tonal and noise masking, quality-scaled rate-distortion thresholds, bounded packet bit reservoirs, deterministic weighted residue-budget allocation, adaptive rate-distortion residue quantization, setup-driven Floor 1 fitting and residue normalization, forward and inverse channel coupling, nearest active vector-codebook and classbook-constrained multi-pass residue quantization, transactional packet-to-PCM stream decoding with granule trimming, and caller-owned seek indexes for positional files.
- Own runtime-shaped f32 or f64 matrices through a caller allocator. Reuse LU, QR, and SVD objects for solving, inverses, least squares, numerical rank, conditioning, reconstruction, and pseudoinverses outside the realtime path.
- Decode complete MPEG Layer III frames through gapless stream ranges, with explicit bounded resynchronization after damaged regions. Emit checked CBR and VBR MPEG-1, MPEG-2, and MPEG-2.5 frames with exact padding cadence, optional CRC protection, all pair and count1 Huffman codebooks, mid-side or intensity stereo, stateful tonal and temporal masking, bounded main-data reuse for either rate policy, gapless Info or Xing metadata, caller-planned VBRI metadata, composed ID3v2 prefixes and ID3v1 tails, and recoverable memory or file output.
- Read and write BW64 through the same checked 64-bit container core as RF64. Compose aXML and exact CHNA channel allocation, parse all core ADM identifier families, validate typed declaration and reference graphs, expose profiles, tag groups, exact time values, and DirectSpeakers, Objects, Matrix, HOA, and Binaural block models, distinguish external common definitions from required local custom definitions, cross-check physical track mappings, reserve zeroed mapping capacity, and reject inconsistent metadata before file mutation.
- Build single-channel or multichannel polyphase IIR oversampling pipelines with zero through eight runtime-selected stages. Each stage has an independent transition and attenuation specification, reconfiguration is transactional between blocks, and latency can remain fractional or be adjusted to an exact integer.
- Build mixed runtime oversampling lists from equiripple FIR, polyphase IIR, and no-op dummy stages. Real stages can use different upsampling and downsampling specifications. FIR tap selection, exact DC normalization, and dense response verification complete before a configuration becomes active.
- Frame Universal MIDI Packets, use typed channel, utility, endpoint, Flex Data, and Mixed Data Set messages, run UMP endpoint and MIDI-CI Discovery, Endpoint Information, Profile Configuration, Property Exchange, and Process Inquiry transactions, manage bounded remote devices, serve local Profiles and Properties through typed delegates, persist remote Property Exchange caches in caller storage, parse and write Property Exchange headers and standardized device, channel, program, mode, state, synchronization, and controller resources, encode Mcoded7 and zlib+Mcoded7, reassemble bounded segmented data, exchange MIDI-CI ACK and NAK messages, and invalidate MUIDs without allocation.
- Build bundled examples through the reusable component, controller, and processor shells.

Use `zig-vst3` directly if you need raw VST3 control:

- Implement or test a specific SDK interface.
- Build custom component/controller/processor objects.
- Control `queryInterface` behavior and optional interfaces precisely.
- Add ABI fixtures or host-side test helpers.

## Current Example Plugins

The repository includes checked framework examples and bundled VST3 examples for:

- `gain`: stereo gain with a continuous parameter.
- `mono-gain`: public high-level mono bus negotiation and processing.
- `surround-gain`: public high-level 5.1 bus negotiation and six-channel processing.
- `sidechain-ducker`: stereo processing with an inactive-by-default mono auxiliary sidechain input.
- `aux-output-splitter`: stereo main processing with separate mono and stereo auxiliary outputs.
- `bypass`: bypass metadata and boolean parameter behavior.
- `mode-gain`: enum/list parameter behavior.
- `voice-mix`: unit and program-list metadata with integer parameters.
- `note-gate`: audio gated by note events.
- `event-echo`: input events echoed to an output event bus.
- `event-monitor`: input-only analyzer topology and event inspection helpers.
- `sine-synth`: output-only generator/instrument behavior driven by note input.
- `ara-playback`: f32 and f64 stereo ARA playback with a complete component, controller, main-factory, transactional paged source cache, bounded polyphonic-note, static-tuning, constant and piecewise variable-tempo, constant and changing meter, content-fade analysis, approved tuning overrides, host source and musical-context tempo maps, a bounded overlap-add spectral gain stage with paged-cache fallback, and an eight-tap windowed-sinc renderer with tempo reflection plus content-based head and tail fades.
- `gain`, `bypass`, `mode-gain`, and `voice-mix`: visible native VSTGUI parameter editors on native builds, with protocol-only fallbacks for cross-target bundles.
- `editor-smoke`: protocol-only editor lifecycle and platform-identifier coverage without a GUI toolkit dependency.

Native macOS and Linux validator jobs run the bundled examples in CI, and a Windows validator job runs the Steinberg validator against the cross-built Windows bundles. Real-host rows are still future work.

## Requirements

- Zig 0.16.0
- VST3 SDK `v3.8.0_build_66`, fetched by the project scripts when needed

See [docs/toolchain.md](docs/toolchain.md) for the exact pinned versions.

## Install

Zig has no central package registry, so `zig-vst3` is fetched by URL from a released tag. Add it to your project with `zig fetch`, pointing at the tag tarball:

```sh
zig fetch --save=zig_vst3 https://github.com/joshburgess/zig-vst3/archive/refs/tags/zig-vst3-0.2.1.tar.gz
```

That records the dependency and its content hash in your `build.zig.zon`. Then wire the module you need into your `build.zig`:

```zig
const dep = b.dependency("zig_vst3", .{ .target = target, .optimize = optimize });

// Raw VST3 bindings:
exe.root_module.addImport("zig-vst3", dep.module("zig-vst3"));

// Or the higher-level plugin framework:
exe.root_module.addImport("zig-vst3-plugin", dep.module("zig-vst3-plugin"));

// Add only to a macOS standalone target that uses device MIDI:
exe.root_module.addImport(
    "zig-vst3-coremidi",
    dep.module("zig-vst3-coremidi"),
);

// Add only to a macOS standalone target that uses device audio:
exe.root_module.addImport(
    "zig-vst3-coreaudio",
    dep.module("zig-vst3-coreaudio"),
);

// Add only to a macOS standalone target with a top-level window:
exe.root_module.addImport(
    "zig-vst3-cocoawindow",
    dep.module("zig-vst3-cocoawindow"),
);

// Add only to a Windows standalone target that uses device audio:
exe.root_module.addImport(
    "zig-vst3-wasapi",
    dep.module("zig-vst3-wasapi"),
);

// Add only to a Windows standalone target that uses MIDI 1 devices:
exe.root_module.addImport(
    "zig-vst3-winmidi",
    dep.module("zig-vst3-winmidi"),
);

// Add only to a Windows standalone target that uses UMP devices:
exe.root_module.addImport(
    "zig-vst3-winump",
    dep.module("zig-vst3-winump"),
);

// Add only to a Windows standalone target with a top-level window:
exe.root_module.addImport(
    "zig-vst3-winwindow",
    dep.module("zig-vst3-winwindow"),
);

// Add only to a Linux standalone target that uses device audio:
exe.root_module.addImport(
    "zig-vst3-alsa",
    dep.module("zig-vst3-alsa"),
);

// Or use the optional PipeWire audio backend:
exe.root_module.addImport(
    "zig-vst3-pipewire",
    dep.module("zig-vst3-pipewire"),
);

// Add only to a Linux standalone target that uses MIDI 1 devices:
exe.root_module.addImport(
    "zig-vst3-alsamidi",
    dep.module("zig-vst3-alsamidi"),
);

// Add only to a Linux standalone target that uses UMP devices:
exe.root_module.addImport(
    "zig-vst3-alsaump",
    dep.module("zig-vst3-alsaump"),
);

// Add only to a Linux standalone target with an X11 top-level window:
exe.root_module.addImport(
    "zig-vst3-x11window",
    dep.module("zig-vst3-x11window"),
);

// Add only to a Linux standalone target with a Wayland top-level window:
exe.root_module.addImport(
    "zig-vst3-waylandwindow",
    dep.module("zig-vst3-waylandwindow"),
);
```

Import them in your code with the same names passed to `addImport`. The package also exposes `zig-vst3-plugin-core` for core-only use. Optional device modules link their platform frameworks and libraries only into targets that import them. Native Windows UMP additionally requires the pinned Windows MIDI Services SDK package at build time. See [Plugin Interface](docs/framework/plugin-interface.md#windows-ump-device-backend) for setup details.

## Quick Start

Run the basic checks:

```sh
zig build
zig build test
zig build test-ara
```

Run the local microbenchmarks:

```sh
zig build benchmark
```

Build all native example bundles:

```sh
zig build clean-bundles
zig build bundle-examples
```

Build one example bundle:

```sh
zig build bundle-gain
```

Build the Mono Gain LV2 bundle:

```sh
zig build bundle-lv2-mono-gain
```

When `lv2_validate` and `lv2lint` are installed, run the reproducible external metadata gate:

```sh
zig build lint-lv2-mono-gain
```

Set `LV2_VALIDATE` or `LV2LINT` to explicit executable paths when the tools are outside `PATH`. The gate validates the three generated Turtle files, loads both native descriptors, enables direct-distribution checks, and treats warnings as failures.

CI runs the same gate in an isolated Linux job with the pinned SDK and uploads the validated bundle.

The bundle is written to `zig-out/bundle/zig_vst3_mono_gain.lv2`. The LV2 core wrapper covers audio and control ports, bounded Atom Sequences with typed MIDI channel events, preserved raw system, SysEx, Program Change, and Channel Pressure messages, arbitrary bounded non-MIDI Atom bodies, segmented sample-offset time Position transport, block-length options, freewheeling/offline process-mode signaling, latency, activation, parameter and bounded component state, and optional bounded Worker requests and responses. The UI bridge adapts the shared editor model to native-parent attachment, control-port updates, host writes, optional touch gestures, idle, show, hide, resize, and teardown callbacks. The optional VSTGUI backend supplies parameter-driven sliders, toggles, and menus plus the native child widget. The metadata generator derives ports and presets from declarations, accepts validated project, license, maintainer, description, live-use, and UI declarations, and publishes the linked VSTGUI UI resource and binary on supported desktop targets. The generated bundle passes independent RDF schema validation and warning-fatal `lv2lint` 0.16.2 validation in direct-distribution mode. External-host confirmation, advanced custom-component bindings, and dynamic bus topology remain open.

Build target bundle layouts:

```sh
zig build -Dtarget=x86_64-linux-gnu bundle-examples-linux
zig build -Dtarget=x86_64-windows-gnu bundle-examples-windows
```

## Validator Checks

On native macOS or Linux, build the Steinberg validator and validate the example bundles:

```sh
zig build validator
zig build validate-examples
```

The broader raw API gate is:

```sh
zig build raw-api-abi
```

`raw-api-abi` compares Zig declarations against SDK-backed C++ fixture programs and entry-symbol checks.

Run Tracktion pluginval against the native examples:

```sh
zig build pluginval-examples
```

For the stricter pluginval pass:

```sh
zig build pluginval-strict-examples
```

See [docs/pluginval.md](docs/pluginval.md) for `PLUGINVAL`, strictness, and headless CI options.

## Documentation

- [docs/framework/plugin-interface.md](docs/framework/plugin-interface.md): framework plugin API.
- [docs/framework/parameters.md](docs/framework/parameters.md): parameters, plain/normalized values, smoothing, metadata, and editors.
- [docs/framework/state.md](docs/framework/state.md): binary state format, migration, restore reports, and debug JSON.
- [docs/framework/gui.md](docs/framework/gui.md): toolkit-neutral editor API, VSTGUI adapter, parameter bindings, and telemetry.
- [docs/framework/resources.md](docs/framework/resources.md): bounded background jobs, immutable resource exchange, off-thread reclamation, persistent references, and missing-file recovery.
- [docs/framework/dsp.md](docs/framework/dsp.md): oscillators, compression, bounded resampling, fixed-rate processing, and dynamic latency updates.
- [docs/framework/c-kernels.md](docs/framework/c-kernels.md): downstream C DSP sources, runtime CPU dispatch, visibility, and ownership rules.
- [docs/raw-api.md](docs/raw-api.md): raw VST3 API guide.
- [docs/raw-api-coverage.md](docs/raw-api-coverage.md): raw API coverage map.
- [docs/pluginval.md](docs/pluginval.md): Tracktion pluginval harness.
- [docs/real-host-coverage.md](docs/real-host-coverage.md): remaining real-host GUI and advanced protocol coverage.
- [docs/capability-matrix.md](docs/capability-matrix.md): implemented capabilities, scope decisions, and prioritized plugin-framework gaps.
- [docs/gui-plan.md](docs/gui-plan.md): phased plan for per-instance editors, GUI adapters, platform embedding, and rendering performance.
- [docs/gui-baseline.md](docs/gui-baseline.md): pre-implementation GUI validation and performance baseline.
- [docs/gui-adapter-evaluation.md](docs/gui-adapter-evaluation.md): VSTGUI and custom-renderer spike results and constraints.
- [docs/adr/0001-gui-adapter-boundary.md](docs/adr/0001-gui-adapter-boundary.md): GUI toolkit and adapter boundary decision.
- [docs/stability.md](docs/stability.md): current pre-release compatibility policy.
- [docs/host-matrix.md](docs/host-matrix.md): real host smoke-test results.
- [docs/roadmap.md](docs/roadmap.md): remaining work and validation tiers.

## CI Coverage

The public CI workflow currently runs:

- Linux, macOS, and Windows build and test jobs.
- Linux and macOS raw API ABI checks.
- Linux, macOS, and Windows Steinberg validator checks for bundled examples.
- macOS, Linux, and Windows pluginval checks for bundled examples, including a strictness 10 pass.
- Linux, macOS, and Windows cross-bundle smoke checks.
- Repository prose hygiene checks.

## Current Limits

- The API is early. Expect some naming and organization changes before a public compatibility promise.
- Manual host coverage is currently macOS REAPER-heavy. MIDI-heavy and analyzer/instrument host smoke rows are still being filled in.
- CI validates plugins headlessly with the Steinberg validator and pluginval, but real-host coverage in actual DAWs is still limited.
- The reference editor can build the pinned VSTGUI adapter on native macOS, Windows, and Linux systems. Other toolkits remain optional adapters.
- This project builds plugins, not hosts.
