# zig-vst3

[![CI](https://github.com/joshburgess/zig-vst3/actions/workflows/ci.yml/badge.svg)](https://github.com/joshburgess/zig-vst3/actions/workflows/ci.yml)

Zig bindings and framework experiments for building VST3 audio plugins.

The current tree contains:

- `vst3-zig/`: raw VST3 binding layer
- `zig-plug/`: higher-level plugin framework layer
- `PROJECT_BUILD_PLAN.md`: staged implementation plan
- `CHANGELOG.md`: release notes
- `docs/layer1-api.md`: raw `vst3-zig` API guide
- `docs/layer1-coverage.md`: Layer 1 protocol coverage map
- `docs/layer1-release.md`: `vst3-zig` release checklist

## Current Status

Layer 1 now builds VST3 example plugins that pass Steinberg's official validator on macOS in CI.

Implemented pieces include:

- TUID/FUID byte layout with SDK fixture comparison
- Explicit `FUnknown` vtable prototype
- Atomic reference counting with allocator-backed destruction tests
- Synthetic multi-interface query dispatch
- C ABI harnesses for `FUnknown` and multi-interface dispatch
- `pluginterfaces/base`, `pluginterfaces/gui`, and broad `pluginterfaces/vst` ABI translations
- Platform-specific VST3 module entry exports
- macOS, Linux, and Windows `.vst3` bundle generation for gain, bypass, mode-gain, voice-mix, note-gate, event-echo, event-monitor, and sine-synth examples
- Validator-passing example plugins with component, controller, processor, automatable parameters, sample-accurate parameter updates, state persistence, input events, and output events
- Reusable component and controller shells covering configurable stereo effect/generator buses, default VST3 connection point, optional process-state reset hooks, optional plug-view factory hook, reusable plug-frame, context-menu, parameter-finder, content-scale, Linux run-loop, Wayland host/frame, plugin-compatibility, host-application/wrapper/context, unit-info, and unit/program-data objects, optional XML representation hook, host application context, host channel-context, automation-state, and data-exchange interfaces with deterministic failure outputs, component-handler automation callbacks, component-handler editor/group/context-menu/bus/system-time/progress callbacks with deterministic delegated failure outputs, unit info and unit-handler callbacks, MIDI mapping/learn, note expression, keyswitch, physical UI mapping, parameter helper, unit data, edit-controller extension, process-context requirement, and processor capability interfaces
- Reusable `IBStream`, `ISizeableStream`, `IParameterChanges`, `IParamValueQueue`, `IEventList`, `IMessage`, `IErrorContext`, `IStringResult`, `IString`, `ICloneable`, `IPersistent`, `IAttributes`, `IAttributes2`, `IUpdateHandler`, `IDependent`, `IAttributeList`, `IStreamAttributes`, `IInterAppAudioHost`, `IInterAppAudioConnectionNotification`, `IInterAppAudioPresetManager`, `ITest`, `ITestResult`, `ITestSuite`, `ITestFactory`, `ITestPlugProvider`, and `ITestPlugProvider2` utility objects for state buffers, process automation/event queues, host/plugin notifications, error reporting, dependency updates, cloning adapters, test harnesses, and state/preset metadata, with deterministic failure outputs for fixed-capacity stream, message, attribute, parameter-change, and event-list helpers
- `zig-plug` float, int, bool, and enum parameter descriptors with normalized/plain conversion, display formatting, parsing, unit assignment, atomic value storage, smoothing helpers, and reflected parameter-change construction
- `zig-plug` plugin specs and instances with reflected defaults, plugin/factory/class metadata, lifecycle validation, typed parameter access, bound parameter views, parameter existence, default-state, and default-reset helpers, parameter state header inspection, state read/write with restore reports, debug JSON, and migration validation, and process dispatch for 32-bit and 64-bit audio
- `zig-plug` unit and program-list metadata for host-facing organization, including value-level metadata predicates, named lookup, program-list lookup by unit name, and unit-based program snapshot application
- `zig-plug` process context helpers for typed effect, generator, and analyzer buffers, sample-accurate parameter changes, input events, output events, output-event capacity checks, and attachment-based context construction
- Checked `zig-plug` examples covering gain, bypass, enum mode gain, int voice mix, note gate, event echo, event monitor, and sine synth behavior through the public framework API

## Development

Required toolchain:

- Zig 0.14.0

Run the local checks:

```sh
zig build
zig build test
zig build phase1
```

The public CI workflow runs build and test jobs on Linux, macOS, and Windows, Layer 1 ABI checks on Linux and macOS, macOS validator checks for the example bundles, and Linux, macOS, and Windows cross-bundle smoke checks.

Before tagging `vst3-zig-0.1.0`, follow the Layer 1 release checklist in `docs/layer1-release.md`.

Build and validate the example plugins on macOS:

```sh
zig build validator
zig build validate-examples
```

Build platform bundles:

```sh
zig build bundle-gain
zig build bundle-bypass
zig build bundle-mode-gain
zig build bundle-voice-mix
zig build bundle-note-gate
zig build bundle-event-echo
zig build bundle-event-monitor
zig build -Dtarget=x86_64-linux-gnu bundle-examples-linux
zig build -Dtarget=x86_64-windows-gnu bundle-examples-windows
```

Remove stale generated bundles before host smoke testing:

```sh
zig build clean-bundles
```
