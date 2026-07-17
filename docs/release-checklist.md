# Release Checklist

This checklist is for tagging raw API releases (most recently `zig-vst3-0.2.1`). It tracks release gates for the raw VST3 API package only. `zig-vst3-plugin` can keep evolving after a tag.

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

After the required checks and host matrix rows are in place:

```sh
git tag zig-vst3-0.2.1
git push origin zig-vst3-0.2.1
```
