# pluginval Harness

The pluginval harness runs Tracktion's `pluginval` command-line validator against built VST3 bundles. It is separate from Steinberg's SDK validator: Steinberg's tool checks VST3 conformance, while pluginval stresses host-like lifecycle, parameter, state, and processing behavior.

## Install pluginval

Download a release from:

```text
https://github.com/Tracktion/pluginval/releases
```

On macOS you can also install it with Homebrew:

```sh
brew install --cask pluginval
```

The Homebrew cask installs `pluginval.app` into `/Applications`, which the wrapper already searches.

The wrapper checks `pluginval` on `PATH` and common macOS app locations. Set `PLUGINVAL` when the binary lives elsewhere:

```sh
PLUGINVAL=/path/to/pluginval scripts/pluginval.sh path/to/Plugin.vst3
```

## Run pluginval

Run one bundle:

```sh
zig build pluginval -Dplugin=path/to/Plugin.vst3
```

Run all native example bundles where parallel GUI application launches are reliable:

```sh
zig build pluginval-examples
```

Run the strictness level 10 gate:

```sh
zig build pluginval-strict-examples
```

The aggregate targets serialize their per-plugin runs. Each invocation writes pluginval artifacts under `${TMPDIR:-/tmp}/zig-vst3-pluginval`. Set `PLUGINVAL_OUTPUT_DIR` to retain them elsewhere. The wrapper prints the exact run directory before starting pluginval. `runner-status.txt` records whether the run succeeded, failed, timed out, received a signal, failed during bootstrap, or was interrupted. On macOS, `launchctl-state.txt` preserves the last observed service state. An observed process exit or signal has priority. If the GUI service remains active after validation, the wrapper accepts only `SUCCESS` or `FAILED` as the final nonempty output line, then removes the service.

The default strictness level is `5`, matching pluginval's usual minimum compatibility bar. Override it with `PLUGINVAL_STRICTNESS`:

```sh
PLUGINVAL_STRICTNESS=10 zig build pluginval-examples
```

Pass extra command-line flags with `PLUGINVAL_ARGS`. For Linux CI without a display server, skip GUI tests:

```sh
PLUGINVAL_ARGS=--skip-gui-tests zig build pluginval-examples
```

The per-plugin timeout defaults to 180 seconds. Set an integer from 1 through 3600 with `PLUGINVAL_TIMEOUT_SECONDS` when a slower machine needs a different bound:

```sh
PLUGINVAL_TIMEOUT_SECONDS=300 zig build pluginval-strict-examples
```

On macOS, individual targets such as `zig build pluginval-channel-strip` are useful for isolating one plugin. The aggregate targets now serialize their runs. Earlier aggregate targets scheduled independent validations concurrently, and pluginval 1.0.4 produced repeated crash dialogs during one such run on July 17, 2026. Those specific reports abort in `NSApplication` and `_RegisterApplication` before plugin scanning or loading, so they describe a concurrent pluginval startup failure rather than a plugin result. A later isolated channel-strip run passed the complete strictness-5 suite, including editor open, open while processing, automation, and editor automation.

Do not use the historical concurrent-startup reports to explain an isolated pluginval exit. If an individual target quits unexpectedly after startup, preserve its log and crash report and treat it as a plugin regression until isolation proves otherwise. Stop after the first unexpected exit instead of repeatedly relaunching the process.

On July 20, 2026, the serialized aggregate targets passed all 14 example plugins at strictness 5 and strictness 10 after three Sample Player defects were isolated and fixed. The defects were crossed parameter-backed range clamping, GUI delivery from a worker-thread parameter callback, and a null `createView` name at the VST3 boundary. Each failure stopped the matrix and preserved its artifact directory before another launch. A separate AppKit registration abort occurred before any plugin image loaded and was classified as a launcher failure from its crash stack, not assumed to be a plugin result.

The runner parser, terminal-verdict handling, timeout bounds, signal classification, and public shell syntax are part of `zig build test`. A passing parser test does not replace a real pluginval run. It makes failures from the real run easier to classify and preserves enough state for diagnosis.

The CI pluginval jobs run on macOS, Linux, and Windows. The Linux job installs the pluginval runtime libraries, runs under `xvfb-run`, and sets `--skip-gui-tests` because the runners have no display server. The headless command-line path does not verify native editor behavior.

The Windows job validates the cross-built Windows bundles produced by the cross-compile job. pluginval is a GUI-subsystem application there, so the job launches it with `Start-Process -Wait` (the call does not otherwise block), runs with `--validate-in-process`, and reads the pass/fail result from the `--output-dir` log file rather than the process exit code, which is unreliable on Windows.
