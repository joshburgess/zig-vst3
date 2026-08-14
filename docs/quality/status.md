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
- Recorded Q08 process-view and Q09 MIDI ownership contracts, including
  caller-borrowed slices, fixed-capacity session state, JSON parse arenas, and
  failure-atomic incremental processing.
- Passed 98 focused Q08 test selections and 283 focused Q09 test selections.
  Some import-root and integration tests appear in more than one selection, so
  these counts are evidence per command rather than a unique-test total.
- Recorded Q-MIDI-001 for the Standard MIDI File iterator's quadratic state
  replay and missing explicit parser work limit.
- Recorded Q01, Q05, Q10–Q16, Q20, and non-production ownership dispositions,
  including codecs, files, ADM, dynamic matrices, SOFA, fixed DSP publication,
  GUI import workers, and owning product examples.
- Closed Q-MEM-007 by storing generic plug-view allocator provenance and
  injecting failure at its outer COM allocation.
- Closed Q-MEM-008 by adding a 44-test owning-example gate with failure
  injection for five stable-address processor engines.
- Passed the Vorbis, MP3, matrix, HRTF, HOA, Q12 file and metadata, Q15
  publication, Q16 GUI-model, and Q20 owning-example focused gates.
- Began Phase 2 atomic review while the Phase 1 ADM gate runs. Closed
  Q-CONC-001 by serializing VSTGUI global initialization and exit. Address,
  undefined-behavior, and thread sanitizer gates passed after the fix.
- Added a focused Phase 2 TSan gate for GUI queues and snapshots, standalone
  MIDI and capture queues, and ARA close/read and cache publication overlap.
  The gate passed 14 tests, and the regular concurrent selection passed 15.
- Closed Q-CONC-002 by delivering resource publication callbacks from explicit
  control-thread polling instead of preparation workers. Resource ownership,
  owning-example, native VSTGUI, and resource TSan gates pass after the fix.
- Closed Q-CONC-003 by adding explicit callback admission and drain protocols
  to CoreAudio session and topology callbacks and CoreMIDI input callbacks.
  Deterministic overlap tests pass under TSan.

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

Finish the 210-test focused ADM selection and the exact Phase 1 repository
gate. Then close Phase 1 and continue the Phase 2 atomic, callback-drain, and
realtime-call-graph review.
