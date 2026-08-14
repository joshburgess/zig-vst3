# Quality Program Status

Current phase: Phase 1, Ownership and Memory Safety

Status: in progress

Baseline commit: `08bf883e9d2d324f3a7933fa21851bbd9ffec513`

Phase 0 completion commit: `69403ddd8a41b8a59c6b047f9b87065157e4087d`

## Completed

- Published the quality roadmap on `feature/plugin-gui`.
- Verified both release tags remain at their recorded immutable commits.
- Confirmed pull request 6 remains open, draft, and mergeable.
- Added a checked source classifier covering 811 files across 23 review units.
- Recorded initial risk scores, cross-cutting exposure, invariants, evidence,
  and one provenance finding.
- Validated intended dependency boundaries against imports and reassigned the
  shared convolver by responsibility.
- Recorded generated, imported, fixture, and external oracle provenance plus
  pinned regeneration or integrity mechanisms.
- Ran the complete Debug graph, repository hygiene, source inventory fixture,
  formatting, and diff checks successfully.
- Recorded Q04 component, controller, and runtime-adapter ownership contracts.
- Closed Q-MEM-001 by making owning allocator provenance injectable and testing
  outer-object and nested processor allocation failures.
- Recorded Q06 runtime, Q07 resource, Q02 ARA, and Q03 VSTGUI and Wayland
  ownership contracts with focused Debug and cross-build evidence.
- Closed Q-GUI-001 by balancing LV2 host peak subscriptions during construction
  rollback and normal editor teardown.
- Recorded Q17 LV2 and AUv2 ownership, allocator provenance, host callback
  borrows, and native Core Foundation transfer contracts.
- Closed Q-MEM-003 with injected host-instance allocation failures, testing
  allocator teardown, and integrated LV2 subscription-order coverage.
- Recorded Q18 native audio, MIDI, window, scheduler, and dynamic-library
  ownership and teardown contracts.
- Closed Q-MEM-004 by making ALSA and Windows MIDI initialization
  failure-atomic, including successful retry after an injected device-query
  failure.
- Closed Q-MEM-005 by releasing PipeWire properties on every failure before
  their documented transfer to a stream.
- Enabled full C undefined-behavior instrumentation on all native backend test
  modules and passed the 90-step focused platform matrix.
- Recorded Q19 editor, component-view, accessibility, platform-interface,
  timer, asset, and callback ownership contracts.
- Closed Q-GUI-002 by detaching retained macOS and Windows accessibility
  objects before their borrowed editor state is released.
- Closed Q-MEM-006 by converging partial editor construction, control
  allocation, timer reuse, and foreign registration failure paths on matched
  cleanup.
- Passed 24 VSTGUI ASan/UBSan process runs, four TSan process runs, native and
  cross-platform adapter tests, and 3,171 Zig-to-C++ lifecycle tests.

## Phase 1 Scope

- Audit ownership and failure paths in risk order, beginning with Q04 and then
  its Q06 and Q07 owning dependencies.
- Record allocator provenance, ownership transfer, partial initialization,
  teardown order, retained slices, pointer conversions, and callback context
  lifetimes.
- Add allocation-failure, leak, failure-atomicity, and teardown tests where the
  contract permits deterministic injection.
- Extend native sanitizer evidence across uncovered FFI ownership paths.

## Next Review Target

Review Q08 process context and Q09 MIDI ownership next. These units carry
host-controlled pointers, bounded event storage, stream parser state, session
state, and callback contexts through realtime and incremental processing.
