# Framework Compatibility Policy

`zig-vst3-0.3.0-rc.1` is the first release candidate with a compatibility
boundary for `zig-vst3-plugin`. The repository remains pre-1.0, but declarations
marked compatibility-ready in the [API inventory](api-compatibility.md) follow
the policy below through the `0.3.x` line.

The RC tag is prepared by this milestone but is not created until exact-commit
public CI passes. Until the tag exists, use the candidate commit recorded in the
release checklist.

## Compatibility Boundary

The release archive contains these installed modules:

- `zig-vst3`
- `zig-vst3-plugin`
- `zig-vst3-plugin-core`
- `zig-vst3-ara`
- Optional `zig-vst3-coreaudio`, `zig-vst3-coremidi`, `zig-vst3-wasapi`,
  `zig-vst3-winmidi`, `zig-vst3-winump`, `zig-vst3-alsa`,
  `zig-vst3-alsamidi`, `zig-vst3-alsaump`, `zig-vst3-pipewire`,
  `zig-vst3-cocoawindow`, `zig-vst3-winwindow`, `zig-vst3-x11window`, and
  `zig-vst3-waylandwindow` modules

The compatibility promise covers only declarations classified
compatibility-ready. Experimental declarations and optional platform modules
ship for evaluation but may change before promotion. Their presence in the
archive does not promote them.

Compatibility-ready declarations keep their public name and documented source
contract throughout `0.3.x`. Compatible additions are allowed. A behavior fix
may reject input that the documented contract already declared invalid. Raw
VST3 and ARA ABI mirrors may change when required to follow the pinned upstream
specification, with the change recorded in the release notes.

Zig 0.16.0, VST3 SDK `v3.8.0_build_66` at commit
`9fad9770f2ae8542ab1a548a68c1ad1ac690abe0`, and the bundled ARA 2.3 headers are
the candidate pins. Changing a pin requires a new release candidate and the
complete release gate.

## Changes and Migration

Every public change must fit one of these cases:

| Change | Requirement |
| --- | --- |
| Compatible addition | Classify it in the API manifest, add an installed-package compile fixture, and record it under Added. |
| Behavior change | State the old and new behavior, identify affected declarations, and provide a migration when callers must change. |
| Deprecation | Keep the old declaration working for the rest of the current minor line, name the replacement in docs and release notes, and add installed coverage for both paths. |
| Removal | Remove compatibility-ready declarations only at a minor boundary after deprecation in a published release. Record the last supported release and a direct replacement or state that none exists. |
| Experimental promotion | Supply the external evidence required by the API inventory, document the contract, reclassify the declaration, and add it to the compatibility fixture in a release candidate. |
| Experimental change or removal | Record it in release notes when installed consumers can observe it. No compatibility alias is required unless the project elects to support a migration. |

Parameter IDs, state field IDs, serialized versions, and host-visible class IDs
are compatibility data, not implementation details. Renames retain those IDs or
provide explicit migrations. Additions preserve older-state defaults. Removals
continue accepting older state where the format permits it.

## Release Notes

Each framework release entry records:

- the archive version and tag;
- Zig, VST3 SDK, and ARA pins;
- the compatibility boundary and experimental exclusions;
- additions, behavior changes, deprecations, removals, and promotions;
- a migration for every source-breaking or behavior-breaking change;
- local release-gate results and exact-commit public CI evidence;
- external validation completed and external evidence still open.

The API manifest at
`tests/installed-consumer/framework_api_manifest.zig` is executable release
metadata. A root declaration cannot enter or leave either installed framework
module without an explicit manifest change. The installed consumer suite then
compiles the reviewed entry points from the staged archive.
