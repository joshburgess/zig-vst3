# Changelog

## Unreleased

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
