# Changelog

## zig-vst3-0.3.0-rc.1 - 2026-08-13

### Release Notes

- This is the first release candidate with a compatibility boundary for `zig-vst3-plugin`. Compatibility-ready declarations in the framework API inventory are preserved through the `0.3.x` line. LV2, AUv2, ARA product APIs, VSTGUI, standalone windows, split-device correction, and optional platform modules remain experimental.
- The release is one source archive containing `zig-vst3`, `zig-vst3-plugin`, `zig-vst3-plugin-core`, `zig-vst3-ara`, and the optional platform modules. Shipping in the archive does not promote an experimental module.
- The candidate pins Zig 0.16.0, VST3 SDK `v3.8.0_build_66` at commit `9fad9770f2ae8542ab1a548a68c1ad1ac690abe0`, and the bundled ARA 2.3 headers.
- `scripts/framework_release_candidate_check.sh` passes locally. Staged Debug and ReleaseSafe consumers each pass 16/16 steps and 89/89 tests. The complete ReleaseSafe graph passes 416/416 steps and 7,387/7,393 tests with six documented environment-dependent skips. Plugin-core, LV2, AUv2, and ARA format and cross-target gates pass 164/164 steps and 1,276/1,276 tests. DSP ThreadSanitizer passes 149/149 tests. Resource and VSTGUI sanitizer gates pass 57/57 tests plus four repeated VSTGUI thread-sanitizer processes. Raw ABI and Steinberg validation pass 229/229 steps, with all 24 native example bundles passing 47/47 validator tests. Benchmarks pass 5/5 steps. Public GitHub Actions run `31692950488` passes all 19 jobs at exact candidate commit `7650781a5625c041ec474a5377d859a427a344f3`.
- Two isolated downstream plugin projects consume only the staged archive through Zig package dependencies. The effect covers preparation, stereo processing, automation, resource identity, state migration, class IDs, and a complete native bundle. The instrument covers events, automation, state, resource identity, class IDs, and a complete native bundle. Both bundles pass Steinberg validation. An older consumer fixture proves the documented source migrations, retained parameter identity, ignored retired state, defaulted new state, and preserved class IDs. Initial public run `31717621771` found and isolated a Linux bundle-fixture basename error. Commit `8e70449cd1042fe8ce9f4c6497f612b7d53c6c36` corrects the effect and instrument inner binary names, and replacement run `31725806430` passes all 19 jobs, including downstream tests on Linux, macOS, and Windows and downstream Steinberg validation on Linux and macOS. No candidate defect or compatibility change was found, so the downstream evidence supports publishing `zig-vst3-0.3.0-rc.1` unchanged after explicit tag authorization.
- Annotated tag object `93a81b7eaac446882775cd6fb0230710c2125755` publishes RC1 at exact candidate commit `7650781a5625c041ec474a5377d859a427a344f3`. The public GitHub source archive has SHA-256 `551f3ff77f4fb63e347975ff6abb9e2e21b45e6114c62dccd8bfe47934e9fa5e`. Its extracted package passes 18/18 installed-package steps and 96/96 tests plus every ReleaseSafe effect, instrument, bundle, and upgrade fixture.

### Added

- Added a compile-time declaration manifest for both installed framework module roots. The staged installed-package gate rejects unclassified additions, removals, missing entries, and duplicates.
- Added a framework compatibility policy covering compatible additions, behavior changes, deprecations, removals, experimental promotion, state identity, migration notes, and release evidence.
- Added a release-candidate gate covering staged consumers, the complete ReleaseSafe graph, format and cross-target checks, sanitizers, raw ABI, Steinberg validation, and benchmarks.
- Added a frozen `0.3.0-rc.1` compatibility baseline. It rejects removed or reclassified compatibility-ready module-root declarations unless a complete migration records deprecation, a later minor boundary, the last supported release, a replacement, and release notes.
- Added isolated downstream effect, instrument, and upgrade projects to the complete test graph, release-candidate gate, and Linux and macOS validator CI jobs.

### Changed

- Completed the first structured `zig-vst3-plugin` API review, added an installed-package compile fixture for the supported framework entry points, and documented compatibility candidates separately from integrations that still require external evidence.
- Capture-rate policy and operating-state enums now reserve unknown integer values for additive evolution. Public construction rejects unknown policy values transactionally.
- Removed the unused `zig-vst3-plugin.backendVersion()` forwarding function. Use `zig-vst3-plugin.version`.
- Removed the unused duplicate `zig-vst3-plugin-core.lv2_metadata` path. Use `zig-vst3-plugin-core.lv2.metadata`.
- Set the shared archive and exported package version to `0.3.0-rc.1`. Native bundle metadata uses the corresponding numeric `0.3.0` version.

### Fixed

- Fixed the streaming HRTF producer publication order so ThreadSanitizer no longer reports a race between pending-slot validation and the producer sample-rate write.

## zig-vst3-0.2.1 - 2026-06-18

### Release Notes

- `zig-vst3-0.2.1` is a maintenance release on top of `0.2.0`. It extends headless validation to all three CI platforms and fixes the cross-built bundle layout so the Steinberg validator accepts the Windows and Linux bundles. There are no raw ABI or checked helper behavior removals.
- The local release gate remains `scripts/raw_api_release_check.sh`. Zig 0.16.0 and VST3 SDK `v3.8.0_build_66` remain the toolchain pins.

### Added

- Linux pluginval CI job running the example bundles under `xvfb` at default strictness and strictness 10.
- Windows pluginval CI job validating the cross-built Windows bundles at default strictness and strictness 10.
- Windows Steinberg validator CI job that builds the validator with MSVC and validates the cross-built Windows bundles.

### Fixed

- Cross-built Linux and Windows bundles now name the inner binary to match the bundle directory, as the VST3 specification requires. Earlier cross bundles kept the unsuffixed binary name inside a suffixed bundle directory, which the Steinberg validator rejected when loading the module.

### Changed

- Compatibility class registration uses the SDK `kPluginCompatibilityClass` constant instead of a hardcoded category string.

### Known Gaps

- Real-host (Tier 3) smoke rows remain deferred: the manual host pass is still macOS REAPER-only, and MIDI-heavy, analyzer, and instrument rows are unfilled.
- Windows and Linux CI validation covers the `x86_64` cross bundles. The `aarch64-windows-gnu` bundle is cross-built but not validated, since validation needs an ARM runner.

## zig-vst3-0.2.0 - 2026-06-10

### Release Notes

- `zig-vst3-0.2.0` adds an editor protocol smoke example, a Tracktion pluginval harness, and broader host-context and capability regression coverage on top of the `0.1.0` preview. All changes are additive: no raw ABI declarations or checked helper behavior were removed.
- The local release gate remains `scripts/raw_api_release_check.sh`. pluginval is available as an optional host-like gate through `zig build pluginval-examples` and `zig build pluginval-strict-examples`.
- Zig 0.16.0 and VST3 SDK `v3.8.0_build_66` remain the toolchain pins.

### Added

- `editor-smoke` example plugin: a protocol-only `IPlugView` for exercising editor attach, resize, focus, and removal paths, exported as `editor_smoke_*` modules with native bundle and Steinberg validator coverage.
- Tracktion pluginval harness: `pluginval`, `pluginval-examples`, and `pluginval-strict-examples` build steps, a wrapper script honoring `PLUGINVAL`, `PLUGINVAL_STRICTNESS`, and `PLUGINVAL_ARGS`, and a `docs/pluginval.md` guide.
- Required macOS pluginval CI job running the example bundles at default strictness and strictness 10.
- Combined host-context regression on the gain component covering channel context, automation state, and data exchange across initialization, delegation, block lifecycle, and termination release.
- Data-exchange receiver dispatch coverage through a real component query path.
- Validator-queryable pressure-to-expression physical UI map on the gain controller.
- Factory-level `IPluginCompatibility` class creation through `IPluginFactory3`.
- `docs/real-host-coverage.md` tracking remaining real-host GUI and advanced protocol coverage.

### Changed

- Test plug provider retains returned component and controller interfaces and balances them through `releasePlugIn`.
- Host application factory reports deterministic null-success outputs, and wrapper MPE support uses the SDK defaults while preserving the last accepted settings on delegated failure.
- README release framing now reflects the tagged preview line and drops the pre-tag release-status instructions.

### Known Gaps

- Real-host (Tier 3) smoke rows for note-gate, event-echo output observation, event-monitor, sine-synth, and the new editor-smoke editor remain deferred. The first manual host pass stays macOS REAPER-only.
- pluginval CI is macOS-only. Linux and Windows pluginval coverage is deferred pending a headless install and display strategy per platform.
- Windows validator execution remains deferred until the project has a runner that can build and execute Steinberg's validator reliably.

## zig-vst3-0.1.0 - 2026-05-22

### Release Notes

- `zig-vst3-0.1.0` is intended as the first raw API preview release. The release target is ABI-checked raw VST3 declarations, reusable host/test helper objects, checked example bundles, and a documented pre-release plugin framework.
- The local release gate is `scripts/raw_api_release_check.sh`. It runs `zig build test`, `zig build raw-api-abi`, `zig build validator`, and `zig build validate-examples`.
- `zig build benchmark` runs local microbenchmarks for raw stream helpers, framework process blocks, parameter stores, and state save/load.
- Zig 0.16.0 and VST3 SDK `v3.8.0_build_66` are the release toolchain pins.

### Added

- Public CI for Linux, macOS, and Windows build and test coverage.
- Raw API ABI checks on Linux and macOS.
- macOS and Linux Steinberg validator coverage for bundled example plugins.
- Cross-target bundle smoke checks for Linux, macOS, and Windows.
- Release checklist and local raw API release gate script.
- Local microbenchmark step for raw stream helpers, framework process blocks, parameter stores, and state save/load.
- Raw API guide and protocol coverage map.
- Advanced helpers for interface support, prefetch state, MIDI learn, MIDI 2 mapping, and physical UI mapping.
- Fixed-capacity note-expression and keyswitch metadata helper for raw API tests.
- Basic compatibility metadata JSON fixture helper.
- Test-interface helper coverage for null result messages and suite environment replacement.
- Parameter function-name and compatible-ID remapping helpers.
- Context-menu target delegation and query coverage.
- Base string/error helper coverage for null strings and missing error-message outputs.
- Component-handler delegated automation failure coverage.
- Update-handler coverage for invalid, duplicate, and full dependent registration.
- Speaker helper coverage for arrangement strings, 3D classification, ambisonic conversion rejection, and stale array reset.
- Preset key and chunk helper coverage for taxonomy strings and every preset chunk type.
- Plug-view and content-scale rejection coverage for preserved attachment state and invalid scale factors.
- Linux run-loop coverage for handler query/delegation and invalid timer registration.
- Inter-app audio helper coverage for scheduled UI events, remote control callbacks, preset-manager creation overrides, and connection notifications.
- Unit and program-list helper coverage for fixed string truncation, program metadata, pitch names, and delegated unit/program data operations.
- Capability helper coverage for inflated interface counts, prefetch query behavior, configured MIDI mapping directions, and empty physical UI maps.
- Host-context helper coverage for host-name truncation, delegated instance creation, automation-state failure tracking, and default data-exchange lifecycles.
- Static factory coverage for fixed string truncation, invalid class lookup clearing, requested IID forwarding, and failed create output clearing.
- Component shell coverage for `IPluginBase` queries, controller class IDs, invalid bus-info clearing, routing defaults, bus activation, IO mode, and deactivation.
- `StaticFactory3` helper for `IPluginFactory2`/`IPluginFactory3` class metadata, Unicode class metadata, and host-context storage.
- Bundled example plugin factories now expose `IPluginFactory3` metadata through their exported factory objects.

### Changed

- Hardened pinned VST3 SDK fetches with forced checkout, non-recursive submodule updates, and retry handling for transient network failures.

### Known Gaps

- The first manual host pass is macOS REAPER-only. Linux and Windows real-host rows are deferred to a follow-up release.
- Event Echo has scan/load/save/reload coverage in REAPER, but direct output-event host observation is deferred.
- Note Gate MIDI-gated manual host coverage is deferred because it still needs an audio-plus-MIDI route test in a real host.
- Event Monitor analyzer manual host coverage is deferred because it still needs a scan/load/save/reload pass with event input.
- Sine Synth instrument manual host coverage is deferred because it still needs a MIDI-driven instrument pass in a real host.
- Windows bundle generation is covered in CI. Windows validator execution is deferred until the project has a runner that can build and execute Steinberg's validator reliably.
