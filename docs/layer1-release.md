# Layer 1 Release Checklist

This checklist is for tagging `zig-vst3-0.1.0`. It tracks release gates for the raw VST3 layer only. `zig-vst3-plugin` can keep evolving after this tag.

The current release pins are Zig 0.16.0 and VST3 SDK `v3.8.0_build_66`. Keep [toolchain.md](toolchain.md), [stability.md](stability.md), and `CHANGELOG.md` aligned with any release-candidate change.

## Required Checks

Run the local release gate:

```sh
scripts/layer1_release_check.sh
```

If the default `zig` on a machine is not the pinned compiler, run the script with `ZIG=/path/to/zig`.

That script runs:

- `zig build test`
- `zig build layer1-abi`
- `zig build validator` on macOS or Linux
- `zig build validate-examples` on macOS or Linux

Also verify:

- GitHub Actions `CI` passes on `main`
- `CHANGELOG.md` contains the release notes for the tag
- `docs/layer1-coverage.md` matches the release scope
- `docs/stability.md` still describes the API promise accurately

Public CI currently covers:

- Linux, macOS, and Windows build and test jobs
- Linux and macOS Layer 1 ABI checks
- Linux and macOS Steinberg validator checks for bundled examples
- Linux, macOS, and Windows cross-bundle smoke checks

## Host Matrix

Record fresh Tier 3 host smoke tests in `docs/host-matrix.md` before tagging. The minimum release set is:

- Gain, bypass, mode-gain, and voice-mix pass in REAPER on macOS arm64
- Event-echo gets a direct output-event observation pass, or the release notes explicitly defer output-event host observation
- Note-gate gets at least one MIDI-plus-audio route test, or the release notes explicitly defer MIDI-gated manual host coverage
- Event-monitor gets at least one scan/load/save/reload test, or the release notes explicitly defer analyzer manual host coverage
- Sine-synth gets at least one MIDI instrument test, or the release notes explicitly defer instrument manual host coverage

Linux and Windows host rows can remain follow-up work for `0.1.x` if CI bundles keep passing and the release notes call out that the first manual host pass was macOS-only. Do not describe deferred rows as host-proven.

## Tag

After the required checks and host matrix rows are in place:

```sh
git tag zig-vst3-0.1.0
git push origin zig-vst3-0.1.0
```
