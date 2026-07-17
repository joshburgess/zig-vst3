# Stability Policy

This project is pre-release. It is usable for experiments, examples, and early plugin work, but it does not yet make a public compatibility promise.

## Toolchain

The supported Zig version is the exact version in [docs/toolchain.md](toolchain.md). Toolchain upgrades are breaking work unless the changelog says otherwise. They should land as dedicated changes with the release gate passing on the new compiler.

The pinned VST3 SDK version is also part of the tested surface. SDK upgrades should update the toolchain docs, release notes, ABI checks, and validator expectations together.

## Raw VST3 API

`zig-vst3` mirrors VST3 SDK ABI declarations and provides helper objects for tests and shell integration. ABI declarations are expected to track the SDK closely. When an SDK interface is covered by `zig build raw-api-abi`, changes to layout, calling convention, entry symbols, TUID bytes, or result semantics should be treated as release-blocking unless they are intentional SDK-alignment fixes.

Before `zig-vst3-0.1.0`, helper APIs can still change. After `zig-vst3-0.1.0`, raw ABI declarations and checked helper behavior should change only with clear release notes and passing ABI gates.

## Plugin Framework

`zig-vst3-plugin` is the plugin framework package. It is still experimental and may change names, helper organization, process hook shapes, or metadata access patterns before a stable compatibility promise.

The intended direction is stable plugin declarations, reflected parameter metadata, state, automation, events, units, programs, and reusable VST3 shells. Until that promise is made, plugin authors should expect to update code across minor pre-1.0 releases.

### VSTGUI component API

The reviewed authoring surface is `@import("zig-vst3").vstgui`. Parameter descriptions, standard control kinds, explicit theme and layout selection, and the `create*View` functions are exercised by both the component gallery and the Voice Mix editor. Changes to that subset should update both editors and the author guide in the same commit.

Meters, assets, font selection, custom drawing callbacks, and native accessibility bridges remain experimental. The gallery exercises their current implementation, but a second production editor has not yet established a compatibility-worthy contract for them. See [VSTGUI Component Authoring](framework/vstgui-components.md#api-status) for the exact boundary.

## Compatibility Expectations

Every release should state:

- Required Zig version.
- Pinned VST3 SDK version.
- Passing local release gate.
- CI platforms covered.
- Validator coverage.
- Real-host smoke coverage and explicit deferrals.
- Known breaking changes or migration notes.

State compatibility should be preserved when practical. Parameter removals should load older state by ignoring unknown ids. Parameter additions should keep defaults when older state is loaded. Parameter renames should use explicit id migrations.

## Breaking Changes

Breaking changes are acceptable before 1.0, but they should be visible:

- Keep them in dedicated commits or PRs when possible.
- Record them in `CHANGELOG.md`.
- Update the public docs in the same change.
- Keep examples compiling against the new API.

After `zig-vst3-0.1.0`, avoid casual churn in the raw API. Framework churn is still allowed, but it should have a clear reason and migration path.
