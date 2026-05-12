# Handover

Last updated: 2026-05-12

## Current State

The repository is `zig-vst3`. The core raw VST3 library is now consistently named `zig-vst3`; the higher-level plugin framework is `zig-vst3-plugin`, with `zig-vst3-plugin-core` as the pure framework module used by Layer 1 and tests.

The immediate focus has been finishing `zig-vst3` and tightening `zig-vst3-plugin` enough to make it a practical Layer 2 API. Layer 1 is broadly usable: it has translated ABI coverage, reusable VST3 shells, bundled example plugins, validator integration, public CI across macOS, Linux, and Windows, and several host-tested examples. REAPER smoke testing confirmed all bundled examples except `note_gate`, which remains deferred because MIDI testing was not convenient in the old session.

Recent work has concentrated on Layer 2 API polish:

- State diagnostics and migration helpers are exposed through `PluginInstance`.
- Parameter migration validation accepts linear old-id chains while still rejecting independently converging target ids.
- Parameter descriptor diagnostics are exposed through `PluginInstance`.
- `PluginInstance.parameterStateEntryCount()` now uses the reflected parameter set method, which external checked examples instantiate correctly.
- State header metadata, migrated-read, restore-report compatibility, restore-report count, decoded/restored/ignored/accounted/unaccounted presence, aggregate, classification, and state migration diagnostics helpers are bound to a plugin instance.
- `PluginInstance` now exposes normalized plugin, factory, component, and controller metadata accessors.
- `ParameterView` and `ParameterEditor` now forward `ParameterSet` validation helpers, and `PluginInstance` exposes parameter, unit, program-list, unit-set, and program-parameter validation checks.
- Process context timing, block, offset, segment, automation, defaulted automation reads, direct parameter-change and input/output event views, ordered parameter-change id iteration, direct input/output audio views, audio channel/view helpers, valid attachment setters, input-event helper predicates, output-event planning helpers, and direct `PluginSpec` topology flags were added and tested.
- Event routing next-offset helpers, offset-only predicates, and bus/channel/bus-channel iterators were added to `Events`, `EventWriter`, and `ProcessContext`.
- `PluginInstance` now exposes same-plugin parameter value copying.
- `ParameterEditor` now copies values from a bound `ParameterView`.
- Parameter value copy helpers now report how many values were copied.
- `PluginInstance` now exposes migrated parameter id resolution alongside migration diagnostics.
- `PluginInstance` now exposes direct unit root, parent, and program-list relationship helpers.
- `PluginInstance` and `UnitSet` now expose program-list program counts by list display name.
- `ProgramList` and `UnitSet` now expose program names by index.
- `UnitSet` and `PluginInstance` now expose program lookups and duplicate program-name diagnostics by program-list display name, and `PluginInstance` can apply programs by list display name.
- `UnitSet` and `PluginInstance` now expose unit-scoped program counts, names, lookups, indexes, presence checks, and duplicate program-name diagnostics.
- `UnitSet` and `PluginInstance` now expose program parameter snapshot metadata by program-list display name and by unit id/name, including count/emptiness helpers, indexed/id/name lookups, presence checks, and duplicate parameter-id diagnostics.
- `UnitSet` and `PluginInstance` now expose program info metadata by program-list display name and by unit id/name, including count/emptiness helpers, entry/key/name lookups, presence checks, and duplicate info-key diagnostics.
- Program snapshot application now uses the counted parameter store path after pre-validation instead of force-unwrapping a reflected parameter load.
- `ParameterSet`, `ParameterView`, `ParameterEditor`, and `PluginInstance` now expose nullable parameter-change constructors by reflected parameter id and display name.
- `ProcessContext` now exposes the optional attached output-event writer directly for custom writer logic.
- `ProcessContext`, `AudioInputs`, and `AudioOutputs` now expose bounded single-sample audio reads, and outputs also expose bounded sample writes.
- `gain_core` now exercises direct `PluginSpec` topology flags, plugin topology and lifecycle predicates, plugin metadata defaults and overrides, instance-bound plugin metadata accessors, prepare validation, process-context timing and validation, direct process-context audio views, valid process attachment setters including direct output-writer access, direct process parameter-change reads and value views, audio channel, single-sample, and buffer-view helpers including empty direct audio views plus output sample writes, parameter presence predicates, parameter descriptor diagnostics, direct `ParameterSet` metadata, validation, diagnostics, and conversion helpers, direct `PluginInstance` metadata, validation, and conversion wrappers, direct and field-name parameter metadata/default/plain-range/flag/unit/option helpers, direct descriptor handles, direct parameter value storage/editor helpers and aliases, reset aliases, instance-bound parameter handles, bound parameter-view metadata/validation/diagnostics/conversions/reads and index aliases, bound parameter-editor metadata/validation/diagnostics/conversions/edits, copy-from-view, and index aliases, editor process-change counts, lookup-based loads, counted stores, direct parameter-change application, field-name/id/display-name parameter-change constructors, parameter-change value predicates, direct parameter-change view helpers, parameter-change iterators, parameter-change next-offset helpers, counted resets, same-plugin value copying with changed-count reporting, parameter utility values and smoothers, defaulted overall, first/latest, and exact-offset automation reads, per-id and per-offset automation reads, parameter and block segment value helpers, parameter segment iterators, state size constants, state header-only writing, state header metadata and compatibility helpers, ignored/accounted/unaccounted state report helpers, instance-bound state report count, presence, aggregate, and classification helpers, migrated state reads, direct instance state read wrappers, migrated parameter-id resolution, state migration diagnostics, reflected-storage process hooks for `f32` and `f64`, and prepare/deinit/f64 parameter-view lifecycle hook variants.
- `mode_gain_core` now exercises enum option metadata helpers by index, id, display name, and field name through direct `ParameterSet`, direct instance, and bound view/editor helpers.
- `bypass_core` now exercises automatable, read-only, bypass, step-count, and list flag helpers through direct instance helpers and bound view/editor helpers.
- `voice_mix_core` now exercises unit, program-list, program, program-parameter, and program-info helper coverage, including direct unit-set validation, instance-bound validation, direct unit-set unit/program/program-snapshot/info lookups, program-list program-name reads, program-list-name and unit-scoped program parameter/info helper paths, program-list-name and unit-scoped lookup/application helpers, value-level helpers, direct instance unit/program-list lookup helpers, direct unit parent helpers, direct program-list/program lookup by id and name, duplicate helpers, counted and boolean program snapshot application, and duplicate diagnostics.
- `event_echo_core` now uses validated output-event planning and exercises direct event-writer helpers plus append aliases, process-context output-event writer attachment and access, append planning, appends, written-output event views, output event bus/channel iterators, event-output topology metadata, unavailable-writer errors, no-writer fallback helpers, routing, capacity, next-offset, kind-offset, kind emptiness, first/latest, offset/kind predicates, and clearing helpers.
- `event_monitor_core` now exercises direct event validation and classification, direct event-view count, emptiness, first/latest, routing, iterator, segment, next-offset, and only helpers, input-event count, emptiness, first/latest, exact kind-at-offset reads, bus/channel/bus-channel iterators, next-offset, only predicates, input-only analyzer topology metadata, input-only process-context channel predicates, empty input-event fallback helpers, typed event payload views including direct note-off payload access, event retargeting helpers, and bus, channel, and bus-channel routing offset helpers.
- `sine_synth_core` now exercises direct `PluginSpec` output-only generator topology flags, output-only process-context channel predicates, process timing, block duration, sample-offset, remaining-frame helpers, and combined event plus automation process-block segments.
- The C and C++ Layer 1 ABI harness executables now disable C sanitization so Zig 0.14.0 does not pull the Debug C sanitizer runtime into native macOS CI links.
- `scripts/build_validator.sh` now supports local macOS Command Line Tools installs by passing Apple clang paths and the SDK-required `XCODE_VERSION` cache value when full Xcode is not active.
- README and Layer 2 docs were updated to match the current public API.

Before this handoff, local checks were repeatedly run and passing:

```sh
zig build
zig build test
git diff --check
rg -n "<project text-rule markers>" .github docs README.md CHANGELOG.md zig-vst3 zig-vst3-plugin examples build.zig scripts
```

The marker scan exits with status 1 when there are no matches, which is expected.

`zig build validate-examples` was also rerun after the list-name and unit-scoped program metadata helper batch and passed locally against the bundled examples. The local machine has Command Line Tools but not full Xcode, and the validator wrapper now handles that setup.

## Last Known Git State

The worktree was clean before this handover refresh. The latest pushed commits before this refresh were:

- `a7e98bf` Bind program info by unit
- `8c50c52` Bind program parameters by unit
- `4e58579` Bind program info by list name
- `1966ace` Bind program parameters by list name
- `30663fb` Refresh handover after program metadata
- `6308700` Bind unit scoped program diagnostics
- `5ba657d` Bind unit scoped program metadata
- `09ae793` Bind program lookups by list name
- `8beaecb` Refresh handover after parameter constructors
- `613c6ef` Add dynamic parameter change constructors
- `03efb99` Refresh handover after list-name helpers
- `be54d4c` Apply programs by list name
- `0152e7a` Add program list name lookups
- `46d5999` Harden program snapshot application
- `e79b4a3` Refresh handover after audio helpers
- `a4f8c22` Add audio sample access helpers
- `7897404` Expose program names on lists
- `a7cda5a` Count copied parameter values
- `51fa517` Refresh handover after routing iterators
- `e9b647d` Add event routing iterators
- `767f652` Bind program count by name
- `b3ffff0` Expose output event writer access
- `f2b00d5` Bind editor value copying
- `3ba79de` Refresh handover after API polish
- `0d74831` Order parameter change id iteration
- `ea6e6ed` Bind accounted state report helpers
- `3b55ae8` Add parameter change iterators
- `f5c62b8` Bind plugin metadata accessors
- `3fd4ac6` Refresh handover after validator pass
- `ee4eadf` Support CLT validator builds
- `01da017` Bind process audio view helpers
- `f3a4b39` Bind parameter validation helpers
- `c1cd585` Refresh handover after state wrappers
- `5f9b9e7` Bind state header metadata helpers
- `c3351ee` Bind state report classification helpers
- `0a2147b` Refresh handover after ABI fix
- `f808411` Disable C sanitizer for ABI harnesses
- `9d8fc4a` Refresh handover after validation coverage
- `cc688dd` Exercise metadata validation helpers
- `509f9c3` Exercise lifecycle hook variants
- `72cbcbf` Exercise state read wrappers
- `ab1dc13` Exercise view and writer aliases
- `bae332c` Refresh handover after parameter aliases
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

CI checkpoint: after pushing `a7e98bf`, GitHub Actions showed run `25710231748` in progress. The latest completed green checkpoint is `8c50c52` run `25710013746`. The `4e58579` run `25709785109`, `1966ace` run `25709649721`, `30663fb` run `25709156101`, and `09ae793` run `25708877691` also completed successfully. The intermediate `6308700`, `5ba657d`, `8beaecb`, `613c6ef`, `be54d4c`, `0152e7a`, `46d5999`, `e79b4a3`, `a4f8c22`, `a7cda5a`, `e9b647d`, `b3ffff0`, `f2b00d5`, `0d74831`, `ea6e6ed`, and `3b55ae8` runs were cancelled by newer pushes, which is expected for this workflow. The earlier macOS Layer 1 ABI failure on `bae332c` and `9d8fc4a` was the Zig 0.14.0 native C sanitizer link issue with `libubsan_rt.a`; `f808411` fixed it by disabling C sanitization for the ABI harness executables.

## What To Do Next

Keep prioritizing `zig-vst3` and `zig-vst3-plugin` completion before starting broader `zig-vst3-plugin` feature expansion.

Recommended next slices:

1. Continue Layer 2 API symmetry checks in `zig-vst3-plugin/src/process.zig`, `parameters.zig`, `state.zig`, `units.zig`, and `plugin.zig`. Recent passes filled state header/report wrapper gaps, parameter validation wrapper gaps, plugin metadata accessors, parameter-change iterators, direct process audio view gaps, editor value copying, output-writer access, program count by list name, event routing iterators, counted parameter value copying, program name lookup, single-sample audio access, program-list-name lookup/application helpers, program snapshot application hardening, dynamic parameter-change constructors, unit-scoped program metadata and diagnostics, and list-name/unit-scoped program parameter/info metadata helpers. The next pass should look for real API gaps rather than blindly chasing constructor/type aliases.
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
zig build validator
zig build validate-examples
git diff --check
rg -n "<project text-rule markers>" .github docs README.md CHANGELOG.md zig-vst3 zig-vst3-plugin examples build.zig scripts
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
