# Quality Consolidation Roadmap

This program hardens the `0.3.x` implementation before `feature/plugin-gui` is
merged into `main` or substantial feature development resumes. Passing CI is
necessary, but it is not sufficient evidence for the intended quality bar.

The target is systems code with explicit ownership, narrow interfaces, stated
invariants, bounded realtime behavior, and adversarial verification. Claims
must be supported by review records, tests, sanitizer results, or measurements.

## Starting Point

The branch adds roughly 340,000 lines across 458 Zig files. It has broad unit,
integration, package, validation, sanitizer, and downstream coverage. Its size,
FFI surface, codecs, platform integrations, and concurrent realtime paths still
require a separate engineering review.

The public `zig-vst3-0.3.0` tag remains immutable. This program may improve
internals and add compatible checks without rewriting release history.

## Operating Rules

- Freeze unrelated feature work until this program is complete.
- Review by risk. FFI, ownership, concurrency, realtime execution, parsers, and
  persistence take priority over tables and mechanical declarations.
- Keep changes small enough to review. Separate behavior changes from broad
  mechanical cleanup.
- Add a regression test before or with each defect fix when a deterministic
  test is practical.
- Preserve public compatibility unless the compatibility policy explicitly
  permits a change.
- Do not weaken a test, sanitizer, invariant, or validation gate to make a
  failure disappear.
- Record commands and exact results. Do not use "reviewed" or "safe" without
  identifying the reviewed scope and evidence.
- A critical or high-severity finding blocks completion of its phase until it
  is fixed or the user explicitly accepts the residual risk.
- External hardware, host, visual, and audition checks remain separate. Their
  absence does not excuse defects detectable in the repository.
- Do not move release tags, merge the pull request, delete branches, or publish
  releases without explicit authorization.

## Evidence and Tracking

Phase 0 creates `docs/quality/` with these maintained records:

- `inventory.md`: subsystem boundaries, owners, dependencies, size, and risk
- `findings.md`: stable finding IDs, severity, location, status, and resolution
- `verification.md`: commands, environments, results, skips, and artifacts
- `invariants.md`: ownership, thread, realtime, and state-machine contracts
- `concurrency.md`: cross-thread ownership, publication, memory-order, and
  teardown contracts plus the checked synchronization-source inventory
- `atomic-orders.md`: checked per-source counts for explicit Zig, C, and C++
  atomic orders so later synchronization changes require renewed review
- `status.md`: phase state, completed scope, and next review target

Findings use `Q-<area>-<number>` identifiers and one of four severities:

- Critical: memory corruption, use-after-free, data race, ABI unsoundness, or a
  defect capable of silently corrupting user data
- High: leak, deadlock, unbounded realtime behavior, broken transactionality,
  or a major correctness failure on valid input
- Medium: localized correctness, maintainability, or performance risk
- Low: cleanup that does not plausibly hide a correctness defect

A finding is closed only when the record links to the change and its verifying
evidence. Duplicate and rejected findings retain a short rationale.

## Phase 0: Inventory and Risk Model

Build a reproducible inventory of production Zig, C, C++, build, and platform
code. Identify generated data separately from handwritten logic. Map public API,
allocation ownership, FFI boundaries, callback entry points, threads, realtime
paths, persistence formats, parsers, and platform-specific code.

Rank every subsystem by consequence, exposure, complexity, and present test
strength. Split the later phases into review units that fit in one coherent
change or audit record.

Exit criteria:

- Every production source file belongs to one review unit.
- Every review unit has a risk rank and named verification requirements.
- Generated or imported material has provenance and regeneration information.
- The tracking files exist and contain no unclassified high-risk source area.

## Phase 1: Ownership and Memory Safety

Audit allocator provenance, ownership transfer, partial initialization,
`defer` and `errdefer`, teardown ordering, slices retained across calls, pointer
casts, alignment, integer-to-pointer operations, C allocation, and callback
context lifetimes.

Exercise allocation failure at owning APIs where Zig's test allocator can do so
without invalidating the API contract. Add focused leak, failure-atomicity, and
teardown tests. Run address and undefined-behavior sanitizers across native FFI
fixtures and broaden coverage where current gates cover only selected adapters.

Exit criteria:

- Every high-risk owning type has a recorded ownership contract.
- Every high-risk initialization path has allocation-failure evidence or a
  documented reason that injection cannot apply.
- Every FFI allocation and callback context has matched lifetime evidence.
- No open critical or high memory-safety finding remains.
- Relevant debug allocator and sanitizer suites pass.

## Phase 2: Concurrency and Realtime Safety

Map thread ownership and publication for processor state, GUI exchange,
resources, devices, MIDI, HRTF, and teardown. Review every atomic operation and
memory order against a stated happens-before relationship. Review locks,
blocking calls, allocation, logging, file access, and loop bounds reachable from
audio callbacks.

Add deterministic state-machine tests, race-focused stress tests, thread
sanitizer coverage, and bounded-work assertions or measurements where useful.

Exit criteria:

- Every cross-thread value has a documented ownership and publication model.
- Every non-default atomic order has a recorded justification.
- Realtime entry points have an auditable list of permitted operations and
  bounded work.
- Teardown and callback overlap are covered for every asynchronous subsystem.
- No open critical or high concurrency or realtime finding remains.

## Phase 3: Parsers, Codecs, and Persistent State

Audit Ogg/Vorbis, MP3, FLAC, ADM XML, state migration, resource metadata, and
other input-driven code for checked arithmetic, bounded allocation, progress,
transactionality, truncation, malformed input, and deterministic failure.

Create dedicated fuzz targets and seed corpora for the highest-risk parsers.
Preserve failure artifacts and make every discovered defect reproducible. Add
short-read, short-write, truncation, corruption, and limit tests. Compare codec
results with independent implementations where licensing and tooling permit.

Exit criteria:

- Every untrusted-input parser has explicit size and work limits.
- High-risk parsers have fuzz targets, checked-in regression cases, and recorded
  sanitizer-backed runs.
- State loading and migration are failure-atomic.
- Codec conformance claims identify their independent oracle and tolerance.
- No open critical or high parser, codec, or persistence finding remains.

## Phase 4: Architecture and API Refinement

Review dependency direction, module boundaries, public surface area, duplicated
mechanisms, naming, generic complexity, error sets, and file cohesion. Large
files are split only where the split creates a clearer contract. Remove dead
code and accidental abstractions. Prefer direct data flow and explicit state
over indirection that does not enforce an invariant.

Review examples and public documentation as consumer code. Ensure ownership,
thread, realtime, and error contracts that cannot be expressed by types are
documented at the boundary.

Exit criteria:

- Each review unit has one clear responsibility and justified dependencies.
- Public APIs have consistent naming, errors, ownership, and lifecycle rules.
- Large handwritten files have a recorded cohesion decision or are decomposed.
- Compatibility checks cover every compatibility-ready public change.
- No open critical or high architectural or API finding remains.

## Phase 5: Numerical Correctness and Performance

Audit DSP preconditions, finite-value handling, overflow, precision, latency,
channel and layout assumptions, and transactional output behavior. Validate
algorithms against independent references where possible.

Profile representative builds and runtime paths before optimizing. Establish
benchmarks for realtime-critical operations, setup costs, memory use, and code
paths whose complexity could scale with hostile or user-controlled input.

Exit criteria:

- Critical DSP algorithms have independent vectors, identities, or reference
  comparisons with stated tolerances.
- Realtime benchmarks have recorded inputs and regression thresholds.
- Performance changes preserve readable invariants and include measurements.
- No open critical or high numerical or performance finding remains.

## Phase 6: Platform and ABI Review

Audit VST3/COM, VSTGUI C++, LV2, AUv2, ARA, system audio, MIDI, native windows,
and dynamic-library boundaries. Check ABI layout, calling conventions, reference
counts, callback reentrancy, failure translation, platform handles, and teardown
ordering.

Use compile-time layout checks, dynamic fixtures, sanitizers, validators, and
available cross-platform CI. Keep unavailable real-host and hardware checks
explicit instead of inferring success from simulated coverage.

Exit criteria:

- Every ABI boundary has a declaration source and an automated layout or
  behavior check where technically possible.
- Reference counting and callback teardown have adversarial lifecycle tests.
- Automated platform gates pass with every skip accounted for.
- No open critical or high platform or ABI finding remains.

## Phase 7: Whole-Repository Verification

Run the complete ReleaseSafe graph, sanitizer suites, fuzz campaigns, package
archive tests, validators, downstream fixtures, benchmarks, formatting, and
repository hygiene from a clean worktree. Repeat nondeterministic stress tests
enough to make their run count meaningful and record the count.

Review all medium findings. Fix those that could combine into a high-severity
risk or indicate a recurring design weakness. Record any intentionally deferred
medium or low finding with scope and rationale.

Exit criteria:

- All automated gates pass at one exact commit.
- The verification record contains exact commands, results, and environment.
- No critical or high finding is open.
- Deferred findings have explicit rationale and do not undermine a public
  compatibility, memory-safety, realtime, or data-integrity claim.

## Phase 8: Merge Readiness

Perform a final diff and history review, reconcile public documentation with the
implementation, and prepare a concise review summary. Confirm that the exact
candidate is clean, pushed, and green in public CI.

Completion of this phase does not authorize a merge. Present the exact commit,
remaining external checks, deferred findings, and evidence summary to the user.
Wait for explicit authorization before changing pull request state or merging.

## Definition of Done

The program is complete when all phase exit criteria are met at one exact
commit, no critical or high finding remains, all residual risk is visible, and
the repository can reproduce the recorded evidence. The result may be described
as extensively reviewed and hardened. It must not be described as proven free
of memory errors, because testing and review cannot establish that absolute
claim for this class of Zig, C, C++, FFI, and platform code.
