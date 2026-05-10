# Layer 1 Release Checklist

This checklist is for tagging `vst3-zig-0.1.0`. It tracks release gates for the raw VST3 layer only. `zig-plug` can keep evolving after this tag.

## Required Checks

Run the local release gate:

```sh
scripts/layer1_release_check.sh
```

That script runs:

- `zig build test`
- `zig build layer1-abi`
- `zig build validator` on macOS
- `zig build validate-examples` on macOS

Also verify:

- GitHub Actions `CI` passes on `main`

Public CI currently covers:

- Linux, macOS, and Windows build and test jobs
- Linux and macOS Layer 1 ABI checks
- macOS Steinberg validator checks for bundled examples
- Linux, macOS, and Windows cross-bundle smoke checks

## Host Matrix

Record fresh Tier 3 host smoke tests in `docs/host-matrix.md` before tagging. The minimum release set is:

- Gain, bypass, mode-gain, voice-mix, and event-echo pass in REAPER on macOS arm64
- Note-gate gets at least one MIDI-plus-audio route test
- Event-monitor gets at least one scan/load/save/reload test
- Sine-synth gets at least one MIDI instrument test

Linux and Windows host rows can remain follow-up work for `0.1.x` if CI bundles keep passing and the release notes call out that the first manual host pass was macOS-only.

## Tag

After the required checks and host matrix rows are in place:

```sh
git tag vst3-zig-0.1.0
git push origin vst3-zig-0.1.0
```
