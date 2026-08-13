# Release Checklist

The source archive contains the raw VST3 API and plugin framework. Raw-only maintenance releases may use the raw gate below. A compatibility-bearing framework release uses the framework candidate gate and one shared `zig-vst3-*` tag.

The current release pins are Zig 0.16.0 and VST3 SDK `v3.8.0_build_66`. Keep [toolchain.md](toolchain.md), [stability.md](stability.md), and `CHANGELOG.md` aligned with any release-candidate change.

## Required Checks

Run the local release gate:

```sh
scripts/raw_api_release_check.sh
```

If the default `zig` on a machine is not the pinned compiler, run the script with `ZIG=/path/to/zig`.

That script runs:

- `zig build test`
- `zig build raw-api-abi`
- `zig build validator` on macOS or Linux
- `zig build validate-examples` on macOS or Linux

For release-candidate performance sanity, also run:

```sh
zig build benchmark
```

Also verify:

- GitHub Actions `CI` passes on `main`
- `CHANGELOG.md` contains the release notes for the tag
- `docs/raw-api-coverage.md` matches the release scope
- `docs/stability.md` still describes the API promise accurately

Public CI currently covers:

- Linux, macOS, and Windows build and test jobs
- Linux and macOS raw API ABI checks
- Linux and macOS Steinberg validator checks for bundled examples, plus a Windows validator job against the cross-built bundles
- Linux, macOS, and Windows pluginval checks, including a strictness 10 pass
- Linux, macOS, and Windows cross-bundle smoke checks

## Framework Release Candidate

Candidate: `zig-vst3-0.3.0-rc.1`

Package boundary: the single archive defined by `build.zig.zon`. The archive
installs `zig-vst3`, `zig-vst3-plugin`, `zig-vst3-plugin-core`, and the optional
platform modules. Only declarations marked compatibility-ready in the API
inventory receive the `0.3.x` framework compatibility promise.

Pins: Zig 0.16.0, VST3 SDK `v3.8.0_build_66` at commit
`9fad9770f2ae8542ab1a548a68c1ad1ac690abe0`, and bundled ARA 2.3 headers.

Run:

```sh
scripts/fetch_sdk.sh
scripts/framework_release_candidate_check.sh
```

The candidate gate verifies the version and toolchain pins, staged package in
Debug and ReleaseSafe, isolated downstream effect, instrument, and upgrade
projects, the complete ReleaseSafe graph, plugin-core and format cross-builds,
DSP, resource, and VSTGUI sanitizer gates, raw ABI, Steinberg validation of the
downstream and native example bundles, and benchmarks.

Local result on 2026-08-13:

- Staged Debug and ReleaseSafe: 16/16 steps and 89/89 tests in each mode.
- Complete ReleaseSafe graph: 416/416 steps and 7,387/7,393 tests, with six documented environment-dependent skips.
- Plugin-core, LV2, AUv2, and ARA gates: 164/164 steps and 1,276/1,276 tests.
- DSP ThreadSanitizer: 5/5 steps and 149/149 tests.
- Resource and VSTGUI sanitizers: 7/7 steps and 57/57 tests, plus four repeated VSTGUI thread-sanitizer processes.
- Raw ABI and Steinberg validation: 229/229 steps. All 24 native example bundles pass 47/47 validator tests.
- Benchmarks: 5/5 steps.

Public result on 2026-08-13:

- GitHub Actions run `31692950488` passes all 19 jobs at exact candidate commit `7650781a5625c041ec474a5377d859a427a344f3`.

Downstream adoption result on 2026-08-13:

- Two independent plugin projects acquire the staged package without repository-relative source access. Debug and ReleaseSafe effect, instrument, and upgrade tests pass, both complete native bundles pass Steinberg validation, and the older fixture preserves class IDs and migrates retained parameter state while rejecting the two retired source paths for the documented reasons.
- The frozen candidate baseline matches exact commit `7650781a5625c041ec474a5377d859a427a344f3`. The installed gate rejects silent removal or reclassification of every compatibility-ready module-root declaration and requires policy-complete migration records for accepted later-minor removals.
- No framework or package-boundary change was required. The release decision is to publish `zig-vst3-0.3.0-rc.1` unchanged after the downstream-evidence commit passes public CI and the tag action is explicitly authorized.
- Exact public CI commit and run identifiers for this downstream-evidence change are pending the pushed commit and completed workflow.

Before tagging, also complete and record these checks:

- Review [Framework API Compatibility Inventory](framework/api-compatibility.md) and [Framework Compatibility Policy](framework/compatibility-policy.md).
- Confirm the reflected declaration manifest rejects drift and accounts for every installed framework module-root declaration.
- Run the staged installed-package suite. Its public API fixture must compile the compatibility-ready and provisional entry points and reject retired leaks.
- Run the public GitHub Actions matrix at the exact candidate commit.
- Record every removal or behavior change in `CHANGELOG.md`, including a direct migration path.
- Reconcile `README.md`, `docs/stability.md`, framework guides, roadmap, capability matrix, and open-work tracker with the candidate surface.
- Confirm the source tree contains no compatibility-ready declaration still classified as internal leakage, redundant, or insufficiently documented.

The following evidence is external. Keep the affected surface experimental, or
record fresh results before promoting it:

- LV2 core and UI in at least two external hosts.
- AUv2 in a real Apple host and ARA in a real ARA host.
- Live assistive technology, Wayland clipboard, and native visual confirmation for VSTGUI.
- Physical audio, MIDI, disparate-clock, recovery, and standalone-window integration.
- Headphone and loudspeaker audition where a product claim depends on it.

## Host Matrix

Record fresh Tier 3 host smoke tests in `docs/host-matrix.md` before tagging. The minimum release set is:

- Gain, bypass, mode-gain, and voice-mix pass in REAPER on macOS arm64
- Event-echo gets a direct output-event observation pass, or the release notes explicitly defer output-event host observation
- Note-gate gets at least one MIDI-plus-audio route test, or the release notes explicitly defer MIDI-gated manual host coverage
- Event-monitor gets at least one scan/load/save/reload test, or the release notes explicitly defer analyzer manual host coverage
- Sine-synth gets at least one MIDI instrument test, or the release notes explicitly defer instrument manual host coverage

Linux and Windows host rows can remain follow-up work for `0.2.x` if CI bundles keep passing and the release notes call out that the first manual host pass was macOS-only. Do not describe deferred rows as host-proven.

For every release containing GUI changes, record these editor lifecycle checks for at least the reference gain editor:

- Open, close, and reopen while transport is stopped and running.
- Resize from both the host and the editor, including the minimum and maximum constraints.
- Exercise pointer, keyboard, exact text entry, reset, and host automation playback.
- Save and reload with the editor open, then repeat with it closed.
- Open two plugin instances and verify their parameters and windows remain isolated.
- Move the editor between display scales when the host and platform allow it.
- Confirm closing the editor stops editor-only timers, repaint requests, and telemetry production.
- Record the host, host version, operating system, architecture, display scale, and result in `docs/host-matrix.md`.

## Tag

After the framework automated checks pass, tag the release candidate. External
rows remain explicitly experimental and do not block this core-only boundary:

```sh
git tag zig-vst3-0.3.0-rc.1
git push origin zig-vst3-0.3.0-rc.1
```

After the raw release checks and required host matrix rows are in place for a
raw-only maintenance release:

```sh
git tag zig-vst3-0.2.1
git push origin zig-vst3-0.2.1
```
