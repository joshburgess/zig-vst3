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

Run all native example bundles:

```sh
zig build pluginval-examples
```

Run the strictness level 10 gate:

```sh
zig build pluginval-strict-examples
```

The default strictness level is `5`, matching pluginval's usual minimum compatibility bar. Override it with `PLUGINVAL_STRICTNESS`:

```sh
PLUGINVAL_STRICTNESS=10 zig build pluginval-examples
```

Pass extra command-line flags with `PLUGINVAL_ARGS`. For Linux CI without a display server, skip GUI tests:

```sh
PLUGINVAL_ARGS=--skip-gui-tests zig build pluginval-examples
```

The CI pluginval jobs run on macOS, Linux, and Windows. The Linux job installs the pluginval runtime libraries, runs under `xvfb-run`, and sets `--skip-gui-tests` because the runners have no display server. Only `editor-smoke` exposes an editor, and it is a protocol-only view with no toolkit UI, so the headless command-line path stays the expected workflow.

The Windows job validates the cross-built Windows bundles produced by the cross-compile job. pluginval is a GUI-subsystem application there, so the job launches it with `Start-Process -Wait` (the call does not otherwise block), runs with `--validate-in-process`, and reads the pass/fail result from the `--output-dir` log file rather than the process exit code, which is unreliable on Windows.
