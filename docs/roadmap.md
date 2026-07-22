# Roadmap

This file tracks current project work and release readiness.

## Current Focus

`zig-vst3` is the raw VST3 API package. `zig-vst3-plugin` is the higher-level plugin framework package. Both are now exercised by validator-passing example bundles and the public CI matrix.

Near-term work should stay focused on finishing release confidence before adding broad new features:

- Keep the Zig version pinned in `docs/toolchain.md` and CI. Update it only through a dedicated PR.
- Keep the VST3 SDK version pinned in `scripts/fetch_sdk.*` and documented in `docs/toolchain.md`.
- Keep host smoke results in `docs/host-matrix.md`.
- Keep public API docs synchronized with framework changes.

The [Zig NAM readiness plan](nam-zig-readiness-plan.md) uses a neural amp modeler as a production workload for the next framework phase. Configurable bus layouts, generic background resource jobs, immutable exchange, deferred reclamation, fixed-rate conversion, and latency notification are implemented. Resource persistence and missing-file recovery remain next. The model format and inference engine remain a separate library concern.

## Validation Tiers

- Tier 0: `zig build` and `zig build test`.
- Tier 1: `zig build raw-api-abi`.
- Tier 2: `zig build validator` and `zig build validate-examples` on platforms where Steinberg validator support is available.
- Tier 2 optional: `zig build pluginval-examples` and `zig build pluginval-strict-examples` when Tracktion pluginval is installed.
- Tier 3: real host smoke tests recorded in `docs/host-matrix.md`.

For normal code changes, run the smallest tier that covers the changed behavior. For release work, use `scripts/raw_api_release_check.sh` and the checklist in `docs/release-checklist.md`.

## Remaining Work

Highest priority:

- Complete deferred host smoke tests for `note_gate`, `event_echo`, `event_monitor`, and `sine_synth`.
- Keep `docs/framework/plugin-interface.md`, `docs/framework/parameters.md`, `docs/framework/state.md`, and `README.md` aligned with any public API changes.

Medium priority:

- Windows validator support now runs in CI: the Steinberg validator builds with MSVC and validates the cross-built Windows bundles. Remaining Windows work is real-host coverage.
- Broaden host smoke coverage beyond macOS REAPER when practical.
- Expand raw `zig-vst3` docs when new direct-usage workflows appear.
- Finish the platform and real-host rows in [the plugin GUI plan](gui-plan.md). The per-instance object refactor, toolkit-neutral API, macOS reference adapter, and telemetry primitives are implemented.

Release polish:

- Keep `CHANGELOG.md`, `docs/stability.md`, and `docs/release-checklist.md` aligned before tagging public releases.
- Keep `zig build benchmark` useful as focused coverage for raw stream overhead, framework process overhead, parameter update overhead, and state save/load time.

## Framework API Symmetry

The current `zig-vst3-plugin` public surface has had a symmetry pass across `process.zig`, `parameters.zig`, `state.zig`, `units.zig`, and `plugin.zig`.

Current interpretation:

- `ParameterSet`, `ParameterView`, and `ParameterEditor` share the same metadata, validation, conversion, and reflected parameter-change construction surface. `ParameterEditor` adds mutation, reset, copy, and process-change application methods.
- `PluginInstance` exposes the practical instance-bound parameter, unit, program-list, program, state, lifecycle, topology, process, and metadata helpers without forwarding every value-level helper as an alias.
- `UnitSet` retains the broad program metadata lookup surface. `PluginInstance` forwards the host-facing and instance-useful paths, especially list-id, list-name, unit-id, and unit-name program metadata paths.
- `ProcessContext` provides direct input, output, parameter-change, input-event, output-event, timing, segment, and writer helpers. The current distinction between input events, output events, and generic event views is intentional.
- `state` value types provide direct report/header helpers, while `PluginInstance` binds the helpers that need the reflected parameter count.

Do not add aliases only to make every type expose every spelling. Add new API only when a real workflow needs the helper at that API boundary.

## Non-goals

- Hosting plugins. This project builds plugins, not hosts.
- VST2 compatibility.
- A mandatory GUI toolkit. VSTGUI is an optional reference adapter, and users can provide another toolkit.
- Plugin sandboxing or out-of-process hosting.
