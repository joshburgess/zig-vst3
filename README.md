# zig-vst3

Zig bindings and framework experiments for building VST3 audio plugins.

The current tree contains:

- `vst3-zig/`: raw VST3 binding layer
- `zig-plug/`: higher-level plugin framework layer
- `PROJECT_BUILD_PLAN.md`: staged implementation plan

## Current Status

Layer 1 now builds VST3 example plugins that pass Steinberg's official validator locally on macOS.

Implemented pieces include:

- TUID/FUID byte layout with SDK fixture comparison
- Explicit `FUnknown` vtable prototype
- Atomic reference counting with allocator-backed destruction tests
- Synthetic multi-interface query dispatch
- C ABI harnesses for `FUnknown` and multi-interface dispatch
- `pluginterfaces/base`, `pluginterfaces/gui`, and broad `pluginterfaces/vst` ABI translations
- Platform-specific VST3 module entry exports
- macOS, Linux, and Windows `.vst3` bundle generation for gain, bypass, mode-gain, voice-mix, note-gate, and event-echo examples
- Validator-passing example plugins with component, controller, processor, automatable parameters, sample-accurate parameter updates, state persistence, input events, and output events
- Reusable component and controller shells covering default VST3 connection point, optional plug-view factory hook, reusable plug-frame, context-menu, parameter-finder, content-scale, Linux run-loop, Wayland host/frame, and plugin-compatibility objects, optional XML representation hook, host application context, host channel-context, automation-state, and data-exchange interfaces, component-handler automation callbacks, component-handler editor/group/context-menu/bus/system-time/progress callbacks, unit info and unit-handler callbacks, MIDI mapping/learn, note expression, keyswitch, physical UI mapping, parameter helper, unit data, edit-controller extension, process-context requirement, and processor capability interfaces
- Reusable `IMessage`, `IErrorContext`, `IStringResult`, `IString`, `ICloneable`, `IPersistent`, `IAttributes`, `IAttributes2`, `IUpdateHandler`, `IDependent`, `IAttributeList`, `IStreamAttributes`, `IInterAppAudioConnectionNotification`, `IInterAppAudioPresetManager`, `ITest`, and `ITestResult` utility objects for host/plugin notifications, error reporting, dependency updates, cloning adapters, test harnesses, and state/preset metadata
- Initial `zig-plug` float, int, bool, and enum parameter descriptors with normalization tests
- Initial `zig-plug` plugin spec prototype with reflected parameter defaults

## Development

Required toolchain:

- Zig 0.14.0

Run the local checks:

```sh
zig build
zig build test
zig build phase1
```

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
zig build -Dtarget=x86_64-linux-gnu bundle-examples-linux
zig build -Dtarget=x86_64-windows-gnu bundle-examples-windows
```
