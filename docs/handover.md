# Handover

Last updated: 2026-05-11

## Current State

The repository is `zig-vst3`. The core raw VST3 library is now consistently named `zig-vst3`; the higher-level plugin framework is `zig-vst3-plugin`, with `zig-vst3-plugin-core` as the pure framework module used by Layer 1 and tests.

The immediate focus has been finishing `zig-vst3` and tightening `zig-vst3-plugin` enough to make it a practical Layer 2 API. Layer 1 is broadly usable: it has translated ABI coverage, reusable VST3 shells, bundled example plugins, validator integration, public CI across macOS, Linux, and Windows, and several host-tested examples. REAPER smoke testing confirmed all bundled examples except `note_gate`, which remains deferred because MIDI testing was not convenient in the old session.

Recent work has concentrated on Layer 2 API polish:

- State diagnostics and migration helpers are exposed through `PluginInstance`.
- Parameter migration validation accepts linear old-id chains while still rejecting independently converging target ids.
- Parameter descriptor diagnostics are exposed through `PluginInstance`.
- `PluginInstance.parameterStateEntryCount()` now uses the reflected parameter set method, which external checked examples instantiate correctly.
- State header and restore-report compatibility helpers are bound to a plugin instance.
- Process context timing, block, offset, segment, automation, defaulted overall automation reads, and output-event planning helpers were added and tested.
- Event routing next-offset helpers and offset-only event predicates were added to `Events`, `EventWriter`, and `ProcessContext`.
- `PluginInstance` now exposes same-plugin parameter value copying.
- `PluginInstance` now exposes migrated parameter id resolution alongside migration diagnostics.
- `PluginInstance` now exposes direct unit root, parent, and program-list relationship helpers.
- `gain_core` now exercises plugin topology and lifecycle predicates, prepare validation, parameter descriptor diagnostics, direct and field-name parameter metadata/default/plain-range helpers, lookup-based loads, counted stores, direct parameter-change application, counted resets, same-plugin value copying, parameter utility values and smoothers, defaulted overall automation reads, per-id and per-offset automation reads, parameter and block segment value helpers, parameter segment iterators, state header/report compatibility helpers, and migrated parameter-id resolution.
- `mode_gain_core` now exercises enum option metadata helpers by index, id, display name, and field name.
- `bypass_core` now exercises automatable, read-only, bypass, step-count, and list flag helpers.
- `voice_mix_core` now exercises unit, program-list, program, program-parameter, and program-info helper coverage, including value-level helpers and duplicate diagnostics.
- `event_echo_core` now uses validated output-event planning and exercises output-event routing, capacity, next-offset, first/latest, and clearing helpers.
- `event_monitor_core` now exercises typed event payload views, event retargeting helpers, and bus, channel, and bus-channel routing offset helpers.
- `sine_synth_core` now exercises process timing, block duration, sample-offset, and remaining-frame helpers.
- README and Layer 2 docs were updated to match the current public API.

Before this handoff, local checks were repeatedly run and passing:

```sh
zig build
zig build test
git diff --check
rg -n "<project text-rule markers>" .github docs PROJECT_BUILD_PLAN.md README.md CHANGELOG.md zig-vst3 zig-vst3-plugin examples build.zig scripts
```

The marker scan exits with status 1 when there are no matches, which is expected.

## Last Known Git State

The worktree was clean before this handover refresh. The latest pushed commits before this document update were:

- `b86a322` Exercise prepare validation in gain example
- `05ead1e` Exercise plugin lifecycle predicates
- `a167d91` Refresh handover after helper coverage
- `dec52ae` Exercise process timing helpers
- `a754fc0` Exercise process segment value helpers
- `1820d90` Exercise unit program value helpers
- `f934f66` Exercise direct parameter change application
- `e7995a5` Exercise lookup parameter wrappers in gain example
- `ca954cf` Refresh handover after automation coverage
- `ce6f0e5` Exercise automation range helpers in gain example
- `3d87273` Exercise gain field range metadata helpers
- `4cce8ca` Refresh handover after coverage checkpoint
- `8a82332` Exercise gain parameter metadata helpers
- `5ee2f07` Exercise event payload retargeting helpers
- `c31a457` Exercise output event routing helpers
- `842f378` Exercise voice mix duplicate diagnostics
- `1f91346` Refresh handover after checked example pass
- `bf96b44` Exercise parameter flag helpers in bypass example
- `8cfc429` Exercise enum option helpers in mode example
- `5a0e2e5` Exercise parameter utility helpers in gain example
- `5605be1` Exercise state compatibility helpers in gain example
- `7779a9f` Refresh handover after Layer 2 coverage pass

The recent workflow changed to avoid waiting for CI after every push. Use local checks for each coherent batch, push, and only inspect CI at larger checkpoints or after a likely failure.

CI checkpoint: the run for `b86a322` was queued when this handover refresh began. The latest completed non-cancelled run inspected was `ca954cf`, which passed. Intermediate runs after `ca954cf` were cancelled by newer pushes, which is expected for this workflow.

## What To Do Next

Keep prioritizing `zig-vst3` and `zig-vst3-plugin` completion before starting broader `zig-vst3-plugin` feature expansion.

Recommended next slices:

1. Continue Layer 2 API symmetry checks in `zig-vst3-plugin/src/process.zig`, `parameters.zig`, `state.zig`, `units.zig`, and `plugin.zig`. Look for helpers present in lower-level views that are not exposed through `PluginInstance` or examples.
2. Add focused tests whenever a helper is added. Prefer extending nearby existing tests over creating broad new fixtures.
3. Keep docs synchronized in `docs/layer2/plugin-interface.md`, `docs/layer2/parameters.md`, `docs/layer2/state.md`, and `README.md` when public surface changes.
4. Revisit deferred host smoke coverage:
   - MIDI smoke for `note_gate`.
   - Event output observation for `event_echo`.
   - Windows and Linux host or validator smoke where practical.
5. Start broader API docs for raw `zig-vst3` users after the Layer 2 cleanup pass is less active.

Useful local gates:

```sh
zig build test
git diff --check
rg -n "<project text-rule markers>" .github docs PROJECT_BUILD_PLAN.md README.md CHANGELOG.md zig-vst3 zig-vst3-plugin examples build.zig scripts
```

Useful CI command when needed:

```sh
gh run list --branch main --limit 6 --json databaseId,headSha,status,conclusion,name,displayTitle
```

## Project Conventions

- Do not mention generated-assistant involvement in commits, PR descriptions, or docs.
- Do not add pair-author trailers.
- Do not use em dash characters in documentation.
- Keep `AGENTS.md` ignored through `.git/info/exclude`, not `.gitignore`.
- Prefer small, coherent commits with passing local checks.
- Do not wait on CI after every push unless there is a reason to suspect failure.
