# Changelog

## zig-vst3-0.4.0 - 2026-10-23

> Version note: the `zig-vst3-0.3.0` and `zig-vst3-0.3.0-rc.1` tags belong to the separate
> plugin-gui feature line. This release continues from `main` (`0.2.1`) and only migrates the
> framework to Zig 0.17.0.

### Release Notes

- `zig-vst3-0.4.0` migrates the library and its build to Zig 0.17.0. This is a breaking release: the same sources can no longer compile with Zig 0.16.0, because 0.17 removes the array-repeat operator `a ** b` and redefines `@typeInfo` payloads as structs-of-arrays. The `zig-vst3-0.2.1` tag remains the last release for Zig 0.16.0 users.
- One behavioral change that does not fail to compile: Zig 0.17 narrows `@hasDecl` to `pub` declarations. Any `Config` hook (e.g. `clone`, `connect`, `disconnect`, `resizeView`, or the plugin lifecycle hooks) is only detected when it is declared `pub fn`. Hooks that stayed private silently stop being called, so make them `pub` when upgrading. The full suite covers the delegation paths on 0.17.
- The local release gate remains `scripts/raw_api_release_check.sh`. The VST3 SDK pin stays at `v3.8.0_build_66`; the compiler pin moves to 0.17.0.

### Changed

- Migrated the language layer to Zig 0.17: array-repeat expressions now use `@splat`, struct/enum/function reflection reads `field_names`/`field_types`/`field_values`/`param_types`, and untyped `@splat` locals carry explicit array types.
- Migrated `build.zig` to the Zig 0.17 build system: `b.getInstallPath` is gone, so bundle steps now write into a generated output directory (`addOutputDirectoryArg2`) and install it with `addInstallDirectory`, which keeps `--prefix` overrides working; validate and pluginval steps receive that directory through `addDirectoryArg2`, and macOS bundle metadata records the new version.
- CI and documentation pins moved to Zig 0.17.0; `build.zig.zon` declares `minimum_zig_version = "0.17.0"`.

### Fixed

- Hook delegation tests declare their config hooks `pub`, matching the narrowed `@hasDecl` semantics of Zig 0.17.

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
