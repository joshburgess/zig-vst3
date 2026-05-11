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
- State header, migrated-read, restore-report compatibility, and state migration diagnostics helpers are bound to a plugin instance.
- Process context timing, block, offset, segment, automation, defaulted automation reads, direct parameter-change and input/output event views, audio channel/view helpers, valid attachment setters, input-event helper predicates, output-event planning helpers, and direct `PluginSpec` topology flags were added and tested.
- Event routing next-offset helpers and offset-only event predicates were added to `Events`, `EventWriter`, and `ProcessContext`.
- `PluginInstance` now exposes same-plugin parameter value copying.
- `PluginInstance` now exposes migrated parameter id resolution alongside migration diagnostics.
- `PluginInstance` now exposes direct unit root, parent, and program-list relationship helpers.
- `gain_core` now exercises direct `PluginSpec` topology flags, plugin topology and lifecycle predicates, plugin metadata defaults and overrides, prepare validation, process-context timing and validation, valid process attachment setters, direct process parameter-change reads and value views, audio channel and buffer-view helpers including empty direct audio views, parameter presence predicates, parameter descriptor diagnostics, direct `ParameterSet` metadata, diagnostics, and conversion helpers, direct `PluginInstance` metadata and conversion wrappers, direct and field-name parameter metadata/default/plain-range/flag/unit/option helpers, direct descriptor handles, direct parameter value storage/editor helpers and aliases, reset aliases, instance-bound parameter handles, bound parameter-view metadata/diagnostics/conversions/reads, bound parameter-editor metadata/diagnostics/conversions, editor process-change counts, lookup-based loads, counted stores, direct parameter-change application, normalized parameter-change constructors, parameter-change value predicates, direct parameter-change view helpers, parameter-change next-offset helpers, counted resets, same-plugin value copying, parameter utility values and smoothers, defaulted overall, first/latest, and exact-offset automation reads, per-id and per-offset automation reads, parameter and block segment value helpers, parameter segment iterators, state size constants, state header-only writing, state header/report compatibility helpers, ignored/accounted/unaccounted state report helpers, migrated state reads, migrated parameter-id resolution, state migration diagnostics, and reflected-storage process hooks for `f32` and `f64`.
- `mode_gain_core` now exercises enum option metadata helpers by index, id, display name, and field name through direct `ParameterSet`, direct instance, and bound view/editor helpers.
- `bypass_core` now exercises automatable, read-only, bypass, step-count, and list flag helpers through direct instance helpers and bound view/editor helpers.
- `voice_mix_core` now exercises unit, program-list, program, program-parameter, and program-info helper coverage, including direct unit-set unit/program/program-snapshot/info lookups, value-level helpers, direct instance unit/program-list lookup helpers, direct unit parent helpers, direct program-list/program lookup and duplicate helpers, counted and boolean program snapshot application, and duplicate diagnostics.
- `event_echo_core` now uses validated output-event planning and exercises direct event-writer helpers plus process-context output-event writer attachment, append planning, appends, written-output event views, event-output topology metadata, unavailable-writer errors, no-writer fallback helpers, routing, capacity, next-offset, kind-offset, kind emptiness, first/latest, offset/kind predicates, and clearing helpers.
- `event_monitor_core` now exercises direct event validation and classification, direct event-view count, emptiness, first/latest, routing, iterator, segment, next-offset, and only helpers, input-event count, emptiness, first/latest, exact kind-at-offset reads, next-offset, only predicates, input-only analyzer topology metadata, input-only process-context channel predicates, empty input-event fallback helpers, typed event payload views including direct note-off payload access, event retargeting helpers, and bus, channel, and bus-channel routing offset helpers.
- `sine_synth_core` now exercises direct `PluginSpec` output-only generator topology flags, output-only process-context channel predicates, process timing, block duration, sample-offset, remaining-frame helpers, and combined event plus automation process-block segments.
- README and Layer 2 docs were updated to match the current public API.

Before this handoff, local checks were repeatedly run and passing:

```sh
zig build
zig build test
git diff --check
rg -n "<project text-rule markers>" .github docs PROJECT_BUILD_PLAN.md README.md CHANGELOG.md zig-vst3 zig-vst3-plugin examples build.zig scripts
```

The marker scan exits with status 1 when there are no matches, which is expected.

`zig build validate-examples` was also attempted after the one-sided process-context coverage. It failed before running validation because the Steinberg validator was not available: `.vst3-sdk/vst3sdk` is absent and `VST3_VALIDATOR` is not set.

## Last Known Git State

The worktree was clean before this handover refresh. The latest pushed commits before this refresh were:

- `37f94c4` Exercise parameter storage aliases
- `68165fe` Exercise program application aliases
- `36e08dc` Exercise instance parameter wrappers
- `e2077aa` Refresh handover after context coverage
- `af8150e` Exercise note off payload accessor
- `766ca0b` Exercise context wrapper reads
- `2e35b58` Exercise plugin spec topology flags
- `8f4caa2` Document event view segment coverage
- `9bc7541` Refresh handover after event view coverage
- `4de5aa7` Exercise direct input event views
- `a7f56a0` Exercise process parameter change reads
- `3695a86` Exercise direct parameter change views
- `38332bd` Exercise direct unit set program metadata
- `289af53` Exercise exact offset automation defaults
- `3fbe0c3` Exercise direct unit set lookups
- `dab6726` Exercise parameter diagnostics
- `36df13e` Bind state report count helpers
- `0a25848` Refresh handover after audio coverage
- `a09897a` Exercise one-sided process contexts
- `2551e6c` Exercise empty audio buffer views
- `96728c7` Exercise parameter set option metadata
- `68a3f93` Refresh handover after parameter coverage
- `3311c5c` Exercise parameter set metadata
- `b7ba289` Exercise parameter set conversions
- `69fea31` Exercise process attachment setters
- `3adb8fa` Exercise event value helpers
- `ce11fe0` Exercise descriptor conversion helpers
- `e036cd7` Refresh handover after state coverage
- `148bf99` Exercise process event views
- `ec117b3` Exercise migrated state reads
- `518ae0a` Exercise parameter reset aliases
- `cc2d204` Refresh handover after helper coverage
- `88ee0b3` Exercise process timing helpers
- `13c2a1e` Exercise output event append planning
- `3920377` Exercise plugin metadata overrides
- `8dd0992` Exercise field parameter metadata
- `ab369db` Exercise parameter descriptor handles
- `8049180` Exercise normalized parameter changes
- `4b29dd6` Exercise instance unit set handle
- `a715cb5` Exercise checked example topology metadata
- `8931822` Refresh handover after event fallback coverage
- `806eab4` Exercise empty input event helpers
- `007289a` Exercise output event fallback helpers
- `2e4a314` Exercise bound parameter flag metadata
- `c4e8f2f` Exercise program value helpers
- `79c43b5` Refresh handover after segment coverage
- `0278f83` Exercise bound enum option metadata
- `81ccc8b` Exercise process block segments
- `6f09d1b` Exercise instance parameter handles
- `e01be18` Refresh handover after parameter view coverage
- `106a905` Exercise parameter editor conversions
- `8b9e571` Exercise parameter view conversions
- `714a599` Exercise parameter editor metadata
- `8601875` Exercise parameter view metadata
- `ea3c84e` Refresh handover after offset coverage
- `84fcfef` Exercise event writer kind offsets
- `5ab5559` Exercise input event next offsets
- `3901b13` Exercise parameter change next offsets
- `33c5f76` Refresh handover after writer coverage
- `2b08508` Exercise output event writer attachment
- `1549057` Refresh handover after event coverage
- `7f2dfd7` Exercise output event unavailable errors
- `58bb483` Exercise output event context appends
- `2f667f5` Exercise program snapshot counts
- `b52d414` Exercise unit lookup helpers
- `205fc6a` Refresh handover after view coverage
- `969e269` Exercise parameter view reads
- `c42aab3` Exercise state header sizing helpers
- `69b9b9d` Exercise editor change counts
- `7bd4838` Refresh handover after hook coverage
- `e6badd6` Exercise storage process hooks
- `9ee4198` Exercise state migration diagnostics
- `f64ccac` Exercise state header helpers
- `96022e9` Exercise output event predicates
- `601fa5d` Refresh handover after value coverage
- `26fcd0a` Exercise parameter presence predicates
- `b3b4049` Exercise parameter value storage helpers
- `198698c` Exercise event view helpers
- `f112344` Exercise event writer helpers
- `f8ebd9d` Exercise process context validation
- `3a8fbb6` Refresh handover after helper coverage
- `62e3603` Exercise state report helper predicates
- `98f67a6` Exercise parameter change view helpers
- `6ee5a89` Exercise parameter change predicates
- `eb99186` Exercise input event helper predicates
- `78d3720` Exercise audio buffer view helpers
- `f04a83b` Exercise audio channel helpers in gain example
- `b61e5dd` Refresh handover after prepare coverage
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

CI checkpoint: after pushing `37f94c4`, GitHub Actions showed `37f94c4` pending and `68165fe` in progress. The intervening runs for `36e08dc`, `e2077aa`, `af8150e`, `766ca0b`, `2e35b58`, and `8f4caa2` were cancelled by newer pushes, which is expected for this workflow. The latest completed failure inspected earlier was `289af53`, where Windows failed during `mlugg/setup-zig@v2` Zig fetching before the repository build or tests ran; Ubuntu and macOS passed on that commit.

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
