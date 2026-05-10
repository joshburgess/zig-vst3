# Changelog

## Unreleased

### Added

- Public CI for Linux, macOS, and Windows build and test coverage.
- Layer 1 ABI checks on Linux and macOS.
- macOS and Linux Steinberg validator coverage for bundled example plugins.
- Cross-target bundle smoke checks for Linux, macOS, and Windows.
- Layer 1 release checklist and local release gate script.
- Layer 1 raw API guide and protocol coverage map.
- Advanced helpers for interface support, prefetch state, MIDI learn, MIDI 2 mapping, and physical UI mapping.
- Fixed-capacity note-expression and keyswitch metadata helper for raw-layer tests.
- Basic compatibility metadata JSON fixture helper.

### Changed

- Hardened pinned VST3 SDK fetches with forced checkout, non-recursive submodule updates, and retry handling for transient network failures.

### Known Gaps

- Fresh manual host smoke rows are still needed for note-gate, event-monitor, and sine-synth before tagging `vst3-zig-0.1.0`.
