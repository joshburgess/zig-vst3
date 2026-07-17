# Plugin GUI Baseline

This baseline records the state before per-instance plugin objects and visible editors were implemented. The implementation results below use the same machine and commands.

## Environment

| Item | Value |
| --- | --- |
| Date | 2026-07-17 |
| Host | macOS 15.4.1, arm64 |
| Zig | 0.16.0 |
| VST3 SDK | `v3.8.0_build_66` |
| VSTGUI | `76823bd` |
| pluginval | 1.0.4 |

## Automated Gates

These commands pass on the environment above:

```sh
zig build test
zig build raw-api-abi
zig build validate-examples
zig build pluginval-examples
```

`zig build validator` was run before `validate-examples` because the validator binary was not present in the SDK build directory.

## Microbenchmarks

Run:

```sh
zig build benchmark
```

Initial result:

```text
raw IBStream seek/write/read: 17.8 ns/op
framework process block: 543.4 ns/op
parameter value stores: 0.6 ns/op
state save/load: 18.6 ns/op
GUI scalar snapshot store/load: 0.6 ns/op
```

Microbenchmarks vary across runs and machines. Compare changes on the same machine and treat differences within run-to-run noise as inconclusive.

## macOS Host Procedure

Use this procedure for the visible `gain` reference editor:

1. Run `zig build bundle-examples`.
2. Install or link `zig-out/bundle/zig_vst3_gain.vst3` where the host scans VST3 plugins.
3. Rescan plugins and insert `zig-vst3 Gain`.
4. Open and close the editor while transport is stopped.
5. Open and close the editor while transport is running.
6. Resize the host container if the host permits it.
7. Save, close, reopen, and reload the project.
8. Repeat with two plugin instances.

Cross-target gain, bypass, mode-gain, and voice-mix bundles use protocol-only views. Native supported builds use the visible VSTGUI reference editor. `editor-smoke` remains protocol-only on every target.

## Implementation Results

After the per-instance refactor and reference adapter landed on the feature branch:

- `zig build test` passes, including multi-instance controller, component, view, observer, binding, and telemetry tests.
- `zig build raw-api-abi` passes.
- `zig build validate-examples` passes all Steinberg suites. The editor bundle reports 47 passed tests and no failures.
- `zig build pluginval-examples` passes, including editor open, open while processing, automation, and editor automation.
- `zig build bundle-gain-linux -Dtarget=aarch64-linux-gnu` passes with the protocol fallback.
- The latest scalar telemetry snapshot result is 0.7 ns per store/load pair in the local microbenchmark. The latest framework process block result is 405.8 ns. These microbenchmarks vary across runs, so differences at this scale are not evidence of a regression or improvement without repeated samples.

## Rendering Performance Evidence

A strictness-5 pluginval run repeated 50 times completed successfully. A three-second macOS `sample` capture taken during that workload contained 2,461 samples. VSTGUI content drawing appeared in seven sampled milliseconds and did not appear among the dominant top-of-stack functions. The process was predominantly waiting in application event loops, worker queues, and condition variables.

The opt-in VSTGUI profiler was then exercised with three strictness-5 pluginval repetitions. Editor automation produced 65–67 parameter updates and 67–70 content draws per repetition. Average measured content draw time was 44.9–51.3 microseconds, with a maximum of 282.1 microseconds. Ordinary editor-open tests produced two or three initial draws. After the first cold draw, their maximum was below 300 microseconds. The cold-run maximum was 2.60 milliseconds.

The headless visual regression harness adds a smaller repeated warm-draw check containing one live slider and one active peak meter. On the same macOS development machine it averaged 17 microseconds across 200 draws. The test budget remains 300 microseconds per warm draw. This is a regression ceiling, not a claim that every production editor will have the same cost.

Run the repeatable timing check with:

```sh
ZIG_VSTGUI_PROFILE=1 /Applications/pluginval.app/Contents/MacOS/pluginval \
  --strictness-level 5 --repeat 3 zig-out/bundle/zig_vst3_gain.vst3
```

At the 400 by 300 reference size, these results are well below a 16.67 millisecond display interval. They do not justify a render thread, dirty-region bookkeeping beyond VSTGUI invalidation, or double and triple buffered frame state. The profiler remains available so this decision can be revisited for meters, analyzers, and larger editors.

The adapter owns no GPU device, texture upload path, or custom swap chain. VSTGUI owns surface creation and recreation. Consequently, texture, draw-call, and surface-loss metrics do not apply to this reference backend. Repeated open and close operations remain covered by pluginval and the editor lifecycle tests.

A partial real DAW row is recorded for REAPER 7.36 on macOS. It covers stopped and running editor recreation, host and editor resize, keyboard focus and editing, two isolated instances, pointer and keyboard automation recording and playback, save/reload, restored editor opening, and saving with editors closed. Display-scale migration remains open because a second display was unavailable, so automated host-like checks still do not replace that interaction.
