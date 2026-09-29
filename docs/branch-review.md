# Plugin Framework Branch Review

Reviewed on 2026-09-29 at `9865a3a1f0966ac96c49a36018556aeb96c90e7c`,
against `main` at `75c9420e45033863e2314958334c986d281a4b95`.
The documentation corrections following this review do not change implementation.

## Completion Decision

The implemented capability expansion and the quality consolidation program
reached their recorded completion criteria. The branch stopped at a deliberate
handoff before changing the draft pull request's state or merging it. The reviewed
closure commit is `Complete merge readiness review`, and its exact public CI run
[passes all 19 jobs](https://github.com/joshburgess/zig-vst3/actions/runs/31926228675).

This conclusion covers the completed branch milestones. It does not close the
entire project backlog or promote experimental integrations. All 82 quality
findings are closed, but external verification, product-specific API decisions,
and possible cleanup remain in [Open Work](open-work.md).

## History and Delivered Work

The reviewed branch contains 833 linear commits after `main`, with no merge,
WIP, fixup, or squash commits. Its diff contains 879 files, 436,404 insertions,
and 2,521 deletions, including imported headers, generated data, fixtures, and
verification tooling. These totals describe the reviewed implementation head.

| Period | Delivered milestone | Evidence |
| --- | --- | --- |
| July 17–23 | Optional per-instance VSTGUI editors, reusable controls and graphs, production editor examples, resource preparation and recovery, fixed-rate DSP, and model-boundary hardening | GUI plans, [host matrix](host-matrix.md), and [NAM readiness plan](nam-zig-readiness-plan.md) |
| July 28–August 12 | MIDI and UMP protocols, DSP and codecs, ADM/HOA/HRTF rendering, LV2, AUv2, ARA, native standalone backends, and sustained split-device clock correction | [Capability matrix](capability-matrix.md), [stabilization inventory](stabilization-inventory.md), public API guides, and verification records |
| August 13–14 | Framework compatibility review, RC1, isolated downstream adoption and migration fixtures, then stable `0.3.0` publication | [Compatibility inventory](framework/api-compatibility.md), [release checklist](release-checklist.md), and immutable release tags |
| August 14–16 | Nine quality phases covering inventory, ownership, concurrency/realtime, parsers, API/cohesion, numerics/performance, ABI/platforms, aggregate verification, and merge readiness | [Quality status](quality/status.md), [82 closed findings](quality/findings.md), and [verification ledger](quality/verification.md) |

Pull request [6](https://github.com/joshburgess/zig-vst3/pull/6) was created on
July 29 and continues to follow `feature/plugin-gui`. Its original capability
summary and test totals predate the later implementation and quality work.

Stable `zig-vst3-0.3.0` points to `cf3baa5f132df16bdfa5e86d3437e4cfc3295b39`.
The branch includes subsequent hardening and compatible parser-limit additions
recorded under Unreleased in the [changelog](../CHANGELOG.md). Installing the
stable archive does not include those later changes. Both published tags remain
immutable; merging this branch does not publish a new release.

## Verification Supporting Completion

The Phase 7 implementation candidate is
`f8600fffbcf9faf0b9007cc267313b1cd125001e`. Its recorded gate includes:

- Complete ReleaseSafe graph: 465/465 steps, 7,727 tests passed, four skipped.
- Sanitizers: 39/39 steps and 240/240 tests, plus recorded repeated concurrency
  coverage across 48 aggregate runs and four VSTGUI TSan processes.
- All 18 fuzz targets: 1,862,471 new executions without failure.
- Exact Git archive, installed-package, downstream effect, instrument, bundle,
  and upgrade consumers.
- All 23 native example bundles and both downstream bundles passing Steinberg
  validation, plus benchmarks and checked source policies.
- [Public CI at the implementation candidate](https://github.com/joshburgess/zig-vst3/actions/runs/31921757212),
  followed by public CI at the documentation and final closure commits.

The four local skips require two external HRTF datasets, a discoverable
CoreAudio device, and a live PipeWire host. The optional AndroidX VBRI asset was
also unavailable. Required Linux CI downloads the HRTF datasets; recorded
dataset coverage is separate from the local skip accounting.

This follow-up review compared the commit sequence, release boundaries,
module exports, build targets, public guides, plan checklists, finding states,
and CI evidence. Fresh source, parser, realtime, concurrency, atomic-order,
numerics, ABI, cohesion, callback-pointer, production-termination, and
full-history reference checks pass. It did not repeat the full runtime,
sanitizer, or fuzz campaigns; their exact-commit evidence remains in the ledger.

## Work Still Open

- Real VST3 routing and instrument workflows, the Sample Player walkthrough,
  LV2 validation in two external hosts, AUv2 in an Apple host, and ARA products
  in an ARA host. Older REAPER passes do not prove the final branch artifacts.
  Captured REAPER and Cubase crash investigations also remain open in the
  tracker; the recorded stacks do not establish a zig-vst3 cause.
- Physical audio and MIDI timing, hot-plug and recovery, disparate clocks,
  Windows MIDI Services, PipeWire endpoints, and native standalone windows.
- Live Windows and Linux editor embedding, multi-monitor scale changes,
  screen readers, Wayland clipboard exchange, and built-in visual caret and
  selection synchronization.
- Codec audition, headphone and loudspeaker evaluation, complete room-renderer
  comparison, and product dataset and motion-tracker policies.
- Product-driven ADM/HRTF API refinements, typed vendor iXML schemas, further
  LV2 extensions, and optional native-backend consolidation after live evidence.
  AUv3 and AAX are future format work. NAM inference belongs in a separate library.
- Provider removal of historical read-only GitHub pull refs, tracked separately
  from the completed writable-history checks.

These are explicit residual work and scope decisions. No unresolved quality
finding or interrupted implementation milestone was identified by this review.
Experimental status remains governed by the compatibility inventory.
