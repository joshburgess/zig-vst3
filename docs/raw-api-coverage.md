# Raw API Coverage Map

This map separates what is already gated from what remains future hardening. `docs/interface-inventory.md` is the detailed interface list; this file is the release-level summary.

| Area | Current gate | Remaining work |
| --- | --- | --- |
| Core COM and factory ABI | C and C++ harnesses, entry-symbol checks, SDK layout fixtures, static factory and factory3 helper tests, exported example factory3 metadata | More external host traces for factory lifecycle edge cases |
| TUID/FUID byte layout | SDK-backed byte fixture checks | Add checked fixture snapshots for additional non-P0 identifiers if new bugs appear |
| Base interfaces | ABI fixtures and helper tests for streams, persistence, strings, errors, update, compatibility | Expand convenience wrappers only when raw users need them |
| Component/controller/processor | ABI fixtures, reusable shells, Steinberg validator, example plugins, component shell edge-case tests | More real host lifecycle traces across plugin types |
| Parameters and automation | ABI fixtures, fixed queue helpers, shell bridge tests, validator automation tests, interface-support and prefetch helpers | More host automation smoke tests outside REAPER |
| Events and MIDI | ABI fixtures, input/output event helpers, MIDI learn, MIDI 2 mapping, note-expression, and keyswitch helpers; note-gate/event-echo/event-monitor/sine-synth examples | Manual MIDI host tests for note-gate and sine-synth |
| Units and programs | ABI fixtures, unit/program-list helper tests, shell exposure | More host behavior checks for program-list selection |
| GUI/editor protocols | ABI fixtures and helper tests for `IPlugView`, `IPlugFrame`, content scale, Linux run-loop, Wayland, parameter finder, parameter function names, compatible-ID remapping, and context menus; `editor-smoke` bundle exercises protocol-only `IPlugView` creation through pluginval | Real embedded editor tests on macOS, Windows, X11, and Wayland |
| Data exchange and host context | ABI fixtures and host helper tests for data exchange, channel context, automation state, and physical UI mapping; gain component regression covers combined host initialization, delegation, block lifecycle, and termination release for channel context, automation state, and data exchange; gain controller exposes a validator-queryable pressure-to-expression physical UI map | Real host coverage is still absent for data exchange and physical UI mapping |
| Compatibility and wrapper metadata | ABI fixtures, wrapper helper tests, compatibility JSON streaming tests, basic metadata JSON fixture coverage, and factory-level `IPluginCompatibility` class creation coverage | Host-specific compatibility metadata fixtures as real wrapper needs appear |
| Test provider APIs | ABI fixtures plus helper tests for provider creation, retained component/controller returns, release tracking, test result storage, test lifecycle delegation, suite registration, environment replacement, and factory delegation | Real use against Steinberg or host-provided test suites if external harnesses need it |
| Validator | macOS and Linux validator runs in public CI against native VST3 bundles | Windows validator after the project has a runner that can build and execute Steinberg's validator reliably |
| pluginval | Headless wrapper, native example build steps, strictness 10 gate, and required macOS and Linux CI jobs | Extend pluginval CI to Windows once a headless install and display strategy is settled |
| Host smoke | REAPER macOS rows for core audio examples | Event-echo output-event observation, deferred note-gate, event-monitor, and sine-synth rows, plus Linux/Windows hosts |

## Release Interpretation

`zig-vst3-0.1.0` can be a useful raw API release with the host deferrals listed in `CHANGELOG.md`. It should not be described as full VST3 protocol completion. The release claim should be narrower:

- Raw bindings and helpers for the SDK 3.8.0 plugin-facing interface surface tracked in `docs/interface-inventory.md`
- ABI fixtures for the translated interface groups used by the raw API
- Validator-passing example bundles
- CI-covered cross-target build and bundle generation

Future releases can turn individual rows above from "ABI and helper covered" into "host-proven" as more DAWs and platforms are tested.
