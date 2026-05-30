# pluginval Harness

The pluginval harness runs Tracktion's `pluginval` command-line validator against built VST3 bundles. It is separate from Steinberg's SDK validator: Steinberg's tool checks VST3 conformance, while pluginval stresses host-like lifecycle, parameter, state, and processing behavior.

## Install pluginval

Download a release from:

```text
https://github.com/Tracktion/pluginval/releases
```

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

The bundled examples do not provide editors, so the headless command-line path is the expected workflow.
