# Layer 1 Coverage Map

This map separates what is already gated from what remains future hardening. `docs/interface-inventory.md` is the detailed interface list; this file is the release-level summary.

| Area | Current gate | Remaining work |
| --- | --- | --- |
| Core COM and factory ABI | C and C++ harnesses, entry-symbol checks, SDK layout fixtures | More external host traces for factory lifecycle edge cases |
| TUID/FUID byte layout | SDK-backed byte fixture checks | Add checked fixture snapshots for additional non-P0 identifiers if new bugs appear |
| Base interfaces | ABI fixtures and helper tests for streams, persistence, strings, errors, update, compatibility | Expand convenience wrappers only when raw users need them |
| Component/controller/processor | ABI fixtures, reusable shells, Steinberg validator, example plugins | More real host lifecycle traces across plugin types |
| Parameters and automation | ABI fixtures, fixed queue helpers, shell bridge tests, validator automation tests, interface-support and prefetch helpers | More host automation smoke tests outside REAPER |
| Events and MIDI | ABI fixtures, input/output event helpers, MIDI learn and MIDI 2 mapping helpers, note-gate/event-echo/event-monitor/sine-synth examples | Manual MIDI host tests for note-gate and sine-synth |
| Units and programs | ABI fixtures, unit/program-list helper tests, shell exposure | More host behavior checks for program-list selection |
| GUI/editor protocols | ABI fixtures and helper tests for `IPlugView`, `IPlugFrame`, content scale, Linux run-loop, Wayland, parameter finder, context menus | Real embedded editor tests on macOS, Windows, X11, and Wayland |
| Data exchange and host context | ABI fixtures and host helper tests for data exchange, channel context, automation state, and physical UI mapping | Real host coverage is still absent for data exchange and physical UI mapping |
| Compatibility and wrapper metadata | ABI fixtures and compatibility JSON helper tests | More complete compatibility metadata examples |
| Validator | macOS and Linux validator runs in public CI against native VST3 bundles | Windows validator when runners can build and execute Steinberg validator reliably |
| Host smoke | REAPER macOS rows for core audio examples | Deferred note-gate, event-monitor, sine-synth rows plus Linux/Windows hosts |

## Release Interpretation

`vst3-zig-0.1.0` can be a useful raw-layer release once the deferred host rows are filled in. It should not be described as full VST3 protocol completion. The release claim should be narrower:

- Raw bindings and helpers for the SDK 3.8.0 plugin-facing interface surface
- ABI fixtures for the translated interface groups used by the raw layer
- Validator-passing example bundles
- CI-covered cross-target build and bundle generation

Future releases can turn individual rows above from "ABI and helper covered" into "host-proven" as more DAWs and platforms are tested.
