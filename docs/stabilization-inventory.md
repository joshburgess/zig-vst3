# Stabilization Inventory

This tracker records how the 2026-07-28 stabilization batch was divided, committed, and verified. Capability leaves were committed before the aggregate exports and build graph so each intermediate state remained coherent.

Baseline on 2026-07-28:

- 101 modified tracked files
- 226 untracked entries
- 27,701 tracked additions and 841 tracked deletions
- no staged changes
- `git diff --check` passes
- the Zig 0.16.0 build graph loads with a workspace-local global cache

## Capability Groups

| Group | Primary paths | Focused evidence | State |
| --- | --- | --- | --- |
| Foundation and VST3 runtime | `zig-vst3/src/zig_vst3_plugin_effect.zig`, `zig-vst3/src/zig_vst3_plugin_bridge.zig`, `zig-vst3-plugin/src/plugin`, `zig-vst3-plugin/src/resource`, high-level examples | `test-vst3-module`, `raw-api-abi`, example unit tests, lifecycle runners | Integrated in `58c7f69`; complete clean gate passed |
| GUI and VSTGUI adapter | `zig-vst3-plugin/src/gui*`, `zig-vst3/src/vstgui*`, `gui-adapters/vstgui`, GUI examples and runners | `test-gui-lifecycle`, native adapter tests, sanitizer runners where the environment supports them | Committed in `54ac1a9`; clean core passed 1,156/1,156 and final GUI gates passed |
| DSP and audio files | `zig-vst3-plugin/src/dsp`, `tools/benchmark.zig`, DSP fixtures and installed-consumer coverage | public DSP tests, fixture parity, cross-target fixture builds, installed-package tests | Committed in `c0e03f4`; clean DSP module passed 705/705 and final parity gates passed |
| MIDI and MIDI-CI | `zig-vst3-plugin/src/process/midi*`, `mpe*`, `process.zig`, installed-consumer coverage | process module tests, installed-package tests, cross-target compilation | Committed in `e601392`; clean core passed 581/581; grouped and flat public exports were reviewed and verified in `4e8b98b` |
| Standalone and native backends | `zig-vst3-plugin/src/plugin/{standalone,runtime,device_catalog}.zig`, platform backends and shims, native link-smoke tests | `test-coreaudio`, `test-coremidi`, `test-wasapi`, `test-alsa`, `test-alsamidi`, `test-winmidi`, native window and Linux run-loop gates | Committed in `77c2d2d`; clean baseline passed and final native and cross-target gates passed; physical confirmation remains separate |
| LV2 | `zig-vst3-plugin/src/lv2*`, `zig-vst3/src/vstgui_lv2_backend.zig`, Mono Gain LV2 examples, bundle scripts and host fixtures | `test-lv2`, bundle verification, ABI harness, installed-package tests | Committed in `3dead5d`; clean baseline and final LV2 gates passed; external hosts and `lv2lint` remain separate |
| Audio Unit v2 | `zig-vst3-plugin/src/audio_unit*`, AU examples, ABI fixture, bundle script and host fixtures | `test-audio-unit`, AU bundle verification, installed-package tests | Committed in `b5bf73e`; clean baseline and final AUv2 gates passed; Logic and GarageBand remain manual |
| ARA | `zig-vst3/src/ara*`, ARA examples, vendored API headers, ABI tool and check script | `test-ara`, `test-ara-playback-product`, installed-package tests | Committed in `9e09c6f`; clean baseline and final ARA, ABI, and cross-target gates passed; external ARA hosts remain manual |
| Packaging and documentation | `build.zig`, `build.zig.zon`, scripts, README, framework guides, roadmap and open-work trackers | bundle-script tests, installed-package tests, documentation consistency scan | Build and package integration committed in `58c7f69`; documentation reconciled after the clean gate |

## Commit Order

1. MIDI and shared audio-bus topology
2. DSP, audio files, convolution, and serial generations
3. Standalone and native backend leaves
4. LV2 core, UI, metadata, bundles, and fixtures
5. Audio Unit v2 runtime, bundles, and fixtures
6. ARA declarations, controller, playback, ABI, and reference product
7. GUI lifecycle and native VSTGUI adapters
8. Aggregate plugin and VST3 runtimes, examples, build graph, package tests, and verification runners
9. Documentation reconciliation

Two rejected candidate orders proved the dependencies. DSP requires the expanded process transport and shared audio-bus topology. The high-level plugin types require their VST3 adapters and migrated examples in the same integration commit. Tests for rejected orders were not accepted as stabilization evidence.

## Verification Method

For each group:

1. Run the smallest focused gate that covers its public surface and native boundary.
2. Fix failures before moving to another group.
3. Stage only the group and its proven dependencies.
4. Review the staged diff and create one human-readable commit.
5. Check out that commit in a clean temporary worktree.
6. Repeat the focused gate from the clean worktree.

After all groups are assembled:

1. Run installed-package consumers.
2. Run raw ABI checks.
3. Run supported cross-target builds.
4. Run the complete headless `test` step.
5. Keep host, hardware, visual, assistive-technology, and audible results open until they are observed directly.

## Final Automated Evidence

The clean integration commit `58c7f69` passed on 2026-07-28:

- 327/327 build steps
- 5,980/5,983 tests, with two CoreAudio and one CoreMIDI service-availability skips
- installed-package effect, instrument, core, DSP fixture, and C-kernel consumers
- raw API and ARA ABI checks
- native and cross-target standalone, LV2, AUv2, ARA, and DSP fixture builds
- VSTGUI interaction, accessibility, visual, lifecycle, sanitizer-runner, and thread-sanitizer-runner gates
- VST3, LV2, and AUv2 bundle verification
- exact DSP fixture parity
- FFmpeg Vorbis interoperability

AudioToolbox did not expose a Vorbis decoder in this environment, so that decoder check skipped and is not claimed. Manual host, physical-device, visual, assistive-technology, and audible rows remain open in [Open Work](open-work.md).
