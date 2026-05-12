# zig-vst3

[![CI](https://github.com/joshburgess/zig-vst3/actions/workflows/ci.yml/badge.svg)](https://github.com/joshburgess/zig-vst3/actions/workflows/ci.yml)

Zig libraries for building VST3 audio plugins.

This repository has two packages:

- `zig-vst3`: raw Zig bindings and helper objects for the VST3 COM API.
- `zig-vst3-plugin`: a higher-level framework for writing plugins with reflected parameters, state, automation, events, and reusable VST3 shells.

The project currently builds and validates example VST3 bundles for effects, analyzers, event processors, and a MIDI-driven synth. It is still pre-release, but the core path is already covered by unit tests, ABI checks, Steinberg validator runs, and CI on Linux, macOS, and Windows.

## Which Package Should I Use?

Use `zig-vst3-plugin` if you want to write an audio plugin:

- Declare parameters as Zig struct fields.
- Read and write typed parameter values in your processor.
- Use sample-accurate automation, input events, output events, state save/load, and unit/program metadata without hand-writing VST3 COM plumbing.
- Build bundled examples through the reusable component, controller, and processor shells.

Use `zig-vst3` directly if you need raw VST3 control:

- Implement or test a specific SDK interface.
- Build custom component/controller/processor objects.
- Control `queryInterface` behavior and optional interfaces precisely.
- Add ABI fixtures or host-side test helpers.

## Current Example Plugins

The repository includes checked framework examples and bundled VST3 examples for:

- `gain`: stereo gain with a continuous parameter.
- `bypass`: bypass metadata and boolean parameter behavior.
- `mode-gain`: enum/list parameter behavior.
- `voice-mix`: unit and program-list metadata with integer parameters.
- `note-gate`: audio gated by note events.
- `event-echo`: input events echoed to an output event bus.
- `event-monitor`: input-only analyzer topology and event inspection helpers.
- `sine-synth`: output-only generator/instrument behavior driven by note input.

Native macOS and Linux validator jobs run the bundled examples in CI. Windows bundle generation is covered by CI cross-builds; Windows validator and real-host rows are still future work.

## Requirements

- Zig 0.16.0
- VST3 SDK `v3.8.0_build_66`, fetched by the project scripts when needed

See [docs/toolchain.md](docs/toolchain.md) for the exact pinned versions.

## Quick Start

Run the basic checks:

```sh
zig build
zig build test
```

Build all native example bundles:

```sh
zig build clean-bundles
zig build bundle-examples
```

Build one example bundle:

```sh
zig build bundle-gain
```

Build target bundle layouts:

```sh
zig build -Dtarget=x86_64-linux-gnu bundle-examples-linux
zig build -Dtarget=x86_64-windows-gnu bundle-examples-windows
```

## Validator Checks

On native macOS or Linux, build the Steinberg validator and validate the example bundles:

```sh
zig build validator
zig build validate-examples
```

The broader raw API gate is:

```sh
zig build raw-api-abi
```

`raw-api-abi` compares Zig declarations against SDK-backed C++ fixture programs and entry-symbol checks.

## Documentation

- [docs/framework/plugin-interface.md](docs/framework/plugin-interface.md): framework plugin API.
- [docs/framework/parameters.md](docs/framework/parameters.md): parameters, plain/normalized values, smoothing, metadata, and editors.
- [docs/framework/state.md](docs/framework/state.md): binary state format, migration, restore reports, and debug JSON.
- [docs/raw-api.md](docs/raw-api.md): raw VST3 API guide.
- [docs/raw-api-coverage.md](docs/raw-api-coverage.md): raw API coverage map.
- [docs/stability.md](docs/stability.md): current pre-release compatibility policy.
- [docs/host-matrix.md](docs/host-matrix.md): real host smoke-test results.
- [docs/roadmap.md](docs/roadmap.md): remaining work and validation tiers.

## CI Coverage

The public CI workflow currently runs:

- Linux, macOS, and Windows build and test jobs.
- Linux and macOS raw API ABI checks.
- Linux and macOS Steinberg validator checks for bundled examples.
- Linux, macOS, and Windows cross-bundle smoke checks.
- Repository prose hygiene checks.

## Current Limits

- This is pre-release API. Expect some naming and organization changes before a public compatibility promise.
- Manual host coverage is currently macOS REAPER-heavy. MIDI-heavy and analyzer/instrument host smoke rows are still being filled in.
- Windows bundle generation is covered in CI, but Windows validator execution is not.
- There is no bundled GUI toolkit. The raw API exposes editor protocols and the framework can delegate editor creation, but plugin authors bring their own UI stack.
- This project builds plugins, not hosts.

## Release Status

Before tagging `zig-vst3-0.1.0`, follow [docs/release-checklist.md](docs/release-checklist.md). The release checklist requires local gates, green CI, and fresh host smoke rows or explicit release-note deferrals for untested host scenarios.
