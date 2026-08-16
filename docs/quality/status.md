# Quality Program Status

Current phase: Phase 6, Platform and ABI Review

Status: in progress; Phases 0 through 5 complete

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
- Closed Q-MIDI-001 with independent byte, track, event, and payload limits,
  failure-atomic linear iteration, a checked complexity gate, and a dedicated
  native fuzz target. Focused Debug, ReleaseSafe, installed-package, and
  Windows cross-build verification passes.
- Closed Q-CODEC-001 by identifying the exact ISO/IEC 11172-3:1993 sources and
  reconstruction rules for every embedded MP3 Huffman and synthesis-window
  value. Separate semantic SHA-256 checks reject table drift, including a
  verified one-bit negative control.
- Closed Q-ADM-001 with exact linear XML iterator witnesses, explicit ADM byte,
  event, metadata-count, and graph-work limits, and fixed-storage indexes for
  declaration, reference, cardinality, reciprocity, coefficient, and block
  validation. The checked Debug and ReleaseSafe scaling gates, 100,668-run
  native fuzz campaign, installed-package matrix, and Windows cross-build pass.
- Closed Q-PARSE-001 by replacing canonical prefix replay during ordinary
  Vorbis-comment, FLAC-comment, ID3, RIFF INFO, and AIFF text traversal with
  exact retained-state witnesses. The checked six-format scaling gate remains
  flat through 1,024 entries in Debug and ReleaseSafe, and the complete Vorbis
  plus broader Q12 selections pass.
- Closed Q-IXML-001 with bounded default and caller-selected byte,
  structural-work, decoded-text, track, and sync-point policies. The focused
  suite, 100,528-run native fuzz campaign, installed-package matrix, and
  Windows cross-build pass.
- Closed Q-MP3-001 with bounded default and caller-selected encoded-byte and
  frame-count policies for memory and positional-file scans. The complete
  131-test MP3 gate, a further 100,675-run fuzz campaign, and the
  installed-package matrix pass.
- Closed Q-OGG-001 with bounded default and caller-selected encoded-byte,
  page-count, packet-count, and chained-stream policies across memory, file,
  and seek-index paths. The 94-test Vorbis/Ogg gate, 100,094-run native fuzz
  campaign, installed-package matrix, and ReleaseSafe cross-builds pass.
- Closed Q-AUDIO-001 with bounded default and caller-selected file-byte,
  chunk-count, requested-metadata-byte, and PCM-frame policies across WAV,
  AIFF, AIFC, RF64, BW64, and Wave64 readers. The 168-test Q12 selection,
  100,153-run native fuzz campaign, installed-package matrix, and Windows
  ReleaseSafe cross-build pass.
- Closed Q-FLAC-001 with bounded default and caller-selected encoded-byte,
  metadata-block, metadata-byte, PCM-frame, and decoded-frame-block policies
  across memory and positional-file FLAC decoding. The 169-test Q12 selection,
  100,488-run native fuzz campaign, installed-package matrix, and Windows
  ReleaseSafe cross-build pass.
- Closed Q-META-001 with bounded default and caller-selected encoded-byte
  policies across direct ID3v2.3, ID3v2.4, RIFF INFO, AIFF text, and RIFF XML
  parsing. XML attributes now have independent count and source-byte limits.
  The 174-test Q12 selection, 100,017-run native fuzz campaign,
  installed-package matrix, and Windows ReleaseSafe cross-build pass.
- Closed Q-SOFA-001 with a bounded default and caller-selected NetCDF
  file-byte policy enforced before external parsing. Both public datasets,
  independent NetCDF, libmysofa, and libspatialaudio comparisons, the
  installed-package matrix, and Linux plus Windows cross-builds pass.
- Closed Q-STATE-001 by bounding parameter ID migrations at 256, indexing the
  validated table once before state input is read, and fuzzing arbitrary
  parameter-state bytes for failure-atomic restore. The broad state selection,
  Windows cross-build, and installed-package matrix pass.
- Added a checked parser and persistent-state ledger covering 177 production
  sources across eleven input families and four reviewed exclusions. The
  repository gate derives both lexical and semantic filename candidates, and
  negative fixtures prove that omitting either candidate class fails.
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
- Closed Q-MEM-009 and Q-CONC-004 by replacing native MIDI running-flag
  admission with one shared atomic closed-bit and active-count gate. CoreMIDI
  now releases borrowed callbacks after connection failure and normal stop.
- Closed Q-VER-001 by executing the ALSA UMP implementation tests directly
  instead of treating a passing wrapper import test as runtime coverage.
- Passed the complete focused MIDI matrix with 45/45 build steps and 60/60
  tests, then passed 16 repeated aggregate TSan runs covering 64 processes and
  112 selected tests.
- Completed the focused ADM selection with 210/210 tests. The first exact
  repository candidate gate was intentionally stopped after the callback audit
  invalidated that candidate; it remains baseline evidence rather than a pass.
- Closed Q-VER-002 after the next exact gate found that relative imports of the
  shared callback gate collided when several installed backend modules were
  compiled together. The named-module fix passes the focused and installed
  consumer gates.
- Closed Q-VER-003 after the exact gate at `8d93103a` exposed cumulative fake
  host observations shared by two independent LV2 UI lifecycle scenarios. The
  test now verifies and resets the first lifecycle pair, and a dedicated LV2 UI
  adapter gate passes.
- Closed Q-MEM-010 and critical Q-CONC-005 after the continuing ARA audit found
  an unmatched host reader when the destroy callback was absent and a split
  closing/count admission race. The host callback trio is now required before
  acquisition, and one closed-bit lease word linearizes reads with teardown.
  The full ARA matrix and 16 repeated Phase 2 TSan runs pass.
- Closed critical Q-CONC-006 after the continuing callback audit found that
  CoreAudio's separate closure and active-count atomics still allowed a late
  admission after teardown observed zero. Session and topology callbacks now
  use one closed-bit/count gate. The focused matrix and 16 repeated runs pass.
- Closed high-severity Q-RT-001 after the continuing realtime call-graph audit
  found that public host-request and raw `SimpleEffect` topology operations
  could reach the VST3 topology mutex from processing, while raw host dispatch
  could bypass the sink's host-call guard. Realtime audit scopes now reject
  these operations before component locking or host invocation. The focused
  host-request tests and the complete VST3 module gate pass.
- Closed high-severity Q-RT-002 by enforcing the pinned VST3 thread contracts
  for raw channel-context, automation-state, and data-exchange queue lifecycle
  calls. The regression rejects four control-thread host calls from processing
  while preserving realtime data-exchange block lock and free. The complete
  VST3 module gate passes.
- Completed Phase 1 at `db511c18`. The fresh-cache exact repository gate
  passed after an earlier environment-only attempt exhausted the shared
  temporary volume. The successful run covered the repository checks,
  sanitizers, codec and DSP references, downstream consumers, and the
  installed-package matrix without an open critical or high memory-safety
  finding.
- Closed high-severity Q-RT-003 by rejecting realtime use of resource job,
  recovery, decoded-importer, Resource Swap, and Fixed Rate control operations
  before blocking or state mutation. Focused resource, importer, owning-example,
  VST3 module, and resource TSan gates pass.
- Added a checked concurrency record covering 81 source files. It maps
  cross-thread ownership, publication, memory-order, teardown, and realtime
  contracts, and the repository gate now rejects unclassified matching files.
- Closed critical Q-CONC-007 by pinning saturated dynamic and static COM
  reference counts. Saturation can no longer accept an unrepresentable
  reference and then decrement toward premature destruction. Focused lifetime,
  complete VST3 module, and aggregate Phase 2 ThreadSanitizer gates pass.
- Closed Q-CONC-008 by pinning saturated GUI editor activity. An
  unrepresentable open can no longer be followed by decrements that eventually
  disable editor-only processing while an editor remains. Focused telemetry,
  complete VST3 module, and aggregate Phase 2 ThreadSanitizer gates pass.
- Closed high-severity Q-CONC-009 by joining a completed resource worker before
  its thread handle can be replaced. The worker now remains running through
  result disposal and its final queued-work check. Deterministic overlap,
  resource ThreadSanitizer, and owning-example gates pass.
- Added a checked per-source ledger for explicit Zig atomic orders in 57 source
  files. Any count change now fails the repository gate until the corresponding
  publication contract and ledger entry are reviewed together.
- Closed Q-VER-004 by expanding the direct realtime source audit from 18 to all
  26 production example processors and recognizing every public process entry
  form. An exact inventory gate and negative fixture now reject omissions.
- Closed Q-VER-005 by extending the atomic-order ledger to 11 native C and C++
  sources in addition to 57 Zig sources. Independent negative fixtures reject
  changed counts in either language family.
- Recorded critical Q-CONC-010 after native-order review found wrapping COM
  references in the Windows UMP callback. Pinned saturation and deterministic
  plus concurrent regressions pass locally.
- Closed Q-INV-002 by classifying `.cc`, `.cxx`, and `.hpp` sources and counting
  C and C++ atomic syntax in the source inventory.
- Closed critical Q-CONC-010 after GitHub Actions compiled and executed the
  Windows SDK-backed UMP gate successfully in run `31848681596`, Windows job
  `94920244792`.
- Closed high-severity Q-RT-004 by enforcing the successful VST3 negotiated
  maximum block before host input collection or processor invocation.
- Closed high-severity Q-RT-005 by capping parameter queue, parameter point,
  and event host-interface visits even when every reported entry is invalid.
- Recorded the transitive processing chains, shared-state access, failure
  behavior, and concrete work bounds for all 26 production example processors.
  The checked realtime inventory now rejects an omitted contract entry.
- Added decoded-audio importer cancellation and worker join to the focused
  resource ThreadSanitizer gate. The expanded gate passes 60/60 tests.
- Closed Q-VER-006 by making every VSTGUI ThreadSanitizer evidence write
  failure fatal and proving the former false-pass case with a negative fixture.
- Completed the Phase 2 teardown matrix across native callbacks, standalone
  devices, workers, immutable publishers, ARA, HRTF, VSTGUI, and VST3 lifetime
  families. Repeated TSan gates and focused lifecycle suites pass.
- Rejected the first Phase 2 completion candidate after macOS CI exposed a
  second cumulative LV2 UI test counter and an undeclared `rg` dependency in
  the realtime inventory. Commit `a79b294a` closes both verifier defects.
- Expanded Q-VER-008 after the uncached replacement reproduced seven crashes
  on the new macOS 26 ARM `macos-latest` image. Every failed artifact used
  ThreadSanitizer, all unsanitized tests passed, and the same sanitizer gates
  pass on local macOS 15.4. CI now pins the maintained macOS 15 ARM image.
- Closed Q-VER-008 and completed Phase 2 after GitHub Actions run `31858188014`
  at `4466af3d` completed all 19 jobs successfully. The pinned macOS 15 build
  executed the full sanitizer suite, and macOS pluginval passed both normal and
  strictness-10 validation.
- Closed critical Q-ARA-001 by rejecting ARA archive filter counts above model
  capacities before host pointer traversal or fixed-array indexing. Controller
  and tuning-analysis archive restoration is bounded and failure-atomic. The
  complete ARA gate, two fuzz campaigns, TSan, cross-builds, and installed
  package pass.
- Closed Q-MIDI-CI-001 by enforcing the 14-bit Property Exchange header limit
  before allocation. Added a 108-test focused native and cross-target gate plus
  three fuzz targets for wire parsing, failure-atomic reassembly, constrained
  JSON, Mcoded7, resource bodies, and cache restore.
- Opened Q-VER-009 after the complete repository gate found ten older
  termination constructs that postdate its zero-tolerance source scan. The
  other 444/446 steps and 7,556/7,562 tests passed or reached their expected
  platform skips.
- Closed Q-VER-009 by giving test generators safe bounded fallbacks, replacing
  the ADM runtime assertion with a compile-time diagnostic, and handling
  nullable Ogg pages explicitly. The complete repository gate now passes all
  446/446 steps with 7,556 tests passed and six expected platform skips.
- Closed Q-EDITOR-001 by capping editor-state migrations at 256 and replacing
  repeated schema-version scans with one fixed-storage index. Exact-limit,
  transactional, native fuzz, cross-target, and installed-package gates pass.
- Closed Q-RESOURCE-001 by validating direct recovery state before any retained
  state change or worker submission. Fixed-capacity state fuzzing, resource
  ownership, ThreadSanitizer, cross-target, and installed-package gates pass.
- Closed Q-ADAPTER-001 by capping VST3 data-exchange callbacks at 64 blocks
  before raw pointer traversal. The complete adapter review also confirmed
  bounded LV2 feature, option, atom, audio-block, state, and VST3 host-input
  paths. Exact-limit, one-over, VST3, LV2, cross-target, and installed-package
  gates pass.
- Closed Q-MIDI-002 by bounding UMP streams and replacing repeated complete
  replay with an exact validated traversal witness. The checked Debug and
  ReleaseSafe scaling gate stays flat through 4,096 packets, and focused,
  cross-target, installed-package, and 100,367-case generated-input gates pass.
- Closed high-severity Q-MIDI-003 by rechecking ALSA stop requests inside
  native input drains, capping each poll wake at 64 reads, and bounding raw
  MIDI 1 and UMP callback counts before pointer traversal. Native backend,
  ThreadSanitizer, cross-target, and installed-package gates pass.
- Closed P-MIDI after a 102,591-case generated-input campaign preserved the
  complete state of fixed-capacity SysEx7, SysEx8, Mixed Data Set, Flex Data
  text, and Stream text assemblers on every rejected packet.
- Closed Q-EDITOR-002 by replacing the editor-state mutation helper's
  compile-time termination fallback with error propagation. The production
  termination-path scan and focused editor-state gate pass.
- Closed Q-CONFIG-001 and P-CONFIG with exact 128-byte device text limits,
  exhaustive truncation of the maximum 656-byte selection record,
  failure-atomic restore, exact 32-byte VST3 textual IDs, and a dedicated
  native plus ReleaseSafe Windows gate.
- Corrected the parser ledger to remove a nonexistent standalone argument
  parser and classify typed preparation configuration, the bounded event pump,
  and compile-time compatibility JSON output accurately.
- Closed Q-VER-010 after the first completion gate found two stale ALSA acquire
  counts in the atomic-order ledger. The corrected checker, mutation fixture,
  and repeated complete repository gate pass.
- Completed Phase 3 with all parser families closed, no open critical or high
  parser finding, and 446/446 repository steps passing with 7,647 tests passed
  and six expected platform skips.
- Closed Q-ARCH-002 by moving partitioned convolution and realtime publication
  into the DSP layer. HRTF now depends within DSP, while the former GUI module
  remains an exact public compatibility alias. Focused, cross-target,
  ThreadSanitizer, IR Loader, and installed-package gates pass.
- Completed the ADM XML portion of Q-ARCH-001 by moving all public metadata
  traversal behind immutable source views. The remaining core contains one
  document construction and graph-validation contract. Its 125-test gate,
  cross-target compilation, inventories, and installed-package matrix pass.
- Completed the VST3 effect portion of Q-ARCH-001 by separating reflected
  controller construction and shared COM lifetime operations from processor
  and component construction. Exact facade identities, the 796-test VST3
  gate, cross-builds, inventories, and installed-package matrix pass.
- Completed the ARA analysis portion of Q-ARCH-001 by separating tuning,
  tempo and meter, harmony, and polyphonic-note detectors behind shared
  bounded model and validation modules. Exact facade identities, the full
  ARA matrix, archive fuzzing, inventories, and installed consumers pass.
- Completed the MP3 portion of Q-ARCH-001 by separating shared syntax,
  decoder and synthesis state, metadata values, positional reading, reservoir
  credit accounting, and the complete encoder contract behind exact facade
  aliases. The 131-test gate and all ReleaseSafe targets pass.
- Closed Q-ARCH-001 by separating the Ogg container and Vorbis codec behind
  exact facade aliases. Every large handwritten source now has a checked
  `KEEP` decision, and the cohesion inventory contains no `SPLIT` entries.
- Completed the Phase 4 public API review against the executable framework
  manifest, frozen RC1 compatibility baseline, staged installed consumers,
  ownership and realtime ledgers, and framework guides. The compatibility
  policy now reflects the published RC1 and stable 0.3.0 tags.
- Began Phase 5 with the complete local benchmark. Closed Q-PERF-001 by
  replacing repeated least-squares FIR cosine evaluation with one cosine and a
  bounded recurrence per grid row. The unchanged workload improved from
  110.5–111.4 ms to 90.7 ms and passes its 100 ms regression ceiling.
- Closed Q-VER-011 by making the contended snapshot benchmark measure the
  runtime's bounded-attempt contract instead of rejecting an expected
  unavailable result. The complete benchmark passes, including 19,903
  successful publications in 20,000 contended attempts.
- Closed Q-VER-012 after the Phase 5 scope query found that extracted Ogg, MP3,
  ADM, HRTF, and dynamic-matrix submodules fell through to generic Q15. Exact
  directory rules and fixture assertions now cover the intended Q10–Q14
  owners, and the recorded 866-file inventory reflects those boundaries.
- Established the checked Phase 5 numerical ledger across all 100 Q13, Q14,
  and Q15 sources. It records 44 existing evidence dispositions, 39 pending
  numerical reviews, and 17 justified non-numerical exclusions. Negative
  fixtures reject missing, stale, misassigned, and malformed records.
- Accepted the shared ADM and HRTF value review. Exact rational time and sample
  positions, standard speaker mapping, renderer geometry, and right-handed
  HRTF spatial conversion have direct vectors, explicit tolerances, finite and
  transactional coverage. The ledger now has 49 evidence, 33 review, and 18
  excluded records.
- Closed critical Q-MEM-011 after foundational review found that audio-block
  copy could reach overlapping `@memcpy` and arithmetic allowed ambiguous
  shifted aliases. Mutable channels are now disjoint, every source alias is
  checked transactionally, and exact corresponding in-place use remains
  supported. The ledger now has 50 evidence, 32 review, and 18 excluded
  records.
- Closed high Q-MEM-012 after the same audit pattern found shifted input and
  output aliases in six foundational block processor families. A shared
  overflow-safe region classifier preserves exact in-place processing and
  rejects every other overlap before output or state changes. The ledger now
  has 51 evidence, 32 review, and 18 excluded records.
- Accepted phase, denormal control, gain and bias, and logarithmic-ramp
  primitives. Their direct identities, skip equivalence, finite containment,
  transactional mutation, exact control-state restoration, and Debug plus
  ReleaseSafe tests are sound. The ledger now has 55 evidence, 28 review, and
  18 excluded records.
- Closed medium Q-NUM-001 after normalized window application could overflow
  an extreme finite input. Generation and application now preflight every
  derived value and preserve caller storage on failure. Window symmetry,
  normalization, Kaiser references, and both optimized-mode gates pass. The
  ledger now has 56 evidence, 27 review, and 18 excluded records.
- Closed medium Q-NUM-002 after dry/wet weighted sums could overflow finite
  inputs. Mixing now preflights every frame and retains both streams on
  failure. Linear and multiplicative smoothing also passed exact settlement,
  skip, partition, bounded-duration, and hostile-state review. The ledger now
  has 58 evidence, 25 review, and 18 excluded records.
- Closed high Q-NUM-003 after full-domain sweeps exposed excessive exponential
  and near-pole tangent error. Base-2 exponential range reduction and a narrow
  tangent pole fallback preserve the accepted domains and scalar-SIMD parity.
  Dense f32 and f64 reference bounds pass in Debug and ReleaseSafe. The ledger
  now has 59 evidence, 24 review, and 18 excluded records.
- Closed high Q-MEM-013 after three processor-composition adapters accepted
  shifted block aliases. Chains plus independent and shared-state duplicators
  now reject overlap before output or state changes while preserving exact
  in-place use. Polynomial algebra, fitting, orthogonal families, and root
  solving also passed review. The ledger now has 63 evidence, 20 review, and
  18 excluded records.
- Closed high Q-MEM-014 after stereo panning accepted overlapping output
  planes and shifted input aliases. Outputs are now disjoint, and exact
  in-place use remains supported for either output plane. FIR, oscillator, PCM
  dither, and modulation-rate evidence also passed review. The ledger now has
  68 evidence, 15 review, and 18 excluded records.
- Accepted ballistics, biquad, delay, first-order TPT, ladder, lookup-table,
  and state-variable filters. Analytic responses, direct vectors, frequency
  separation, partition invariance, finite containment, alias transactionality,
  and configuration failure behavior pass in Debug and ReleaseSafe. The ledger
  now has 75 evidence, 8 review, and 18 excluded records.
- Closed high Q-MEM-015 across mono and stereo composite effects. Execution-
  order-specific alias contracts now preserve supported in-place use and
  reject ambiguous overlap before output or state changes. Static effect
  vectors, partition behavior, smoothing, stereo tails, shaping identities,
  and containment pass. The numerical ledger is complete with 83 evidence,
  zero review, and 18 excluded records.
- Completed Phase 5 after reconciling every executable performance budget with
  setup, realtime, memory, and hostile-scaling coverage. Five new fixed-storage
  ceilings cover the sample and IR pipelines at their exact benchmark
  capacities. The one-job benchmark passes 5/5 steps and every timing and
  memory threshold. The audit also corrected the recorded least-squares input
  from 255 taps to its actual 63 taps.
- Began Phase 6 with a checked ledger covering all 301 sources in the Q01,
  Q02, Q03, Q04, Q06, Q17, Q18, and Q19 platform-facing review units. Missing,
  stale, duplicate, malformed, and misassigned records fail the repository
  gate. Every source starts in `REVIEW`; prior broad test coverage is not
  accepted until its boundary contract and evidence are inspected.
- Closed Q-VER-014 after the raw ABI matrix was found to ignore configured
  cache roots. All 33 VST3 and ARA comparators now route generated output and
  nested Zig work through the build graph's cache configuration. The routing
  fixture and corrected 135-step raw ABI matrix pass.
- Closed Q-VER-015 after a clean combined validator run exposed missing build
  ordering. Every example validation command now depends directly on the one
  validator build. The clean rerun produced 23/23 successful bundle verdicts.
- Completed the Q01 A-VST3 review across 53 raw declaration and aggregation
  files plus 63 implementation files. The accepted evidence includes the
  pinned SDK matrix, native harnesses, entry symbols, 565 colocated tests,
  adversarial lifetime and concurrency checks, Debug and ReleaseSafe module
  runs with 800/800 tests each, and the 23-bundle native validator run. The ABI
  ledger now has 116 evidence and 185 review records.
- Completed the 21-source Q02 A-ARA review. The official ARA SDK 2.3.001
  headers drive target-specific translated declarations, while the handwritten
  VST3 companion has direct native C++ parity. Factory, controller, model,
  extension, reader, cache, renderer, archive, analysis, callback, and teardown
  evidence passes in Debug, native ReleaseSafe, three ReleaseSafe cross-targets,
  the current TSan selection, and two current 100,000-execution fuzz campaigns.
  The ledger now has 137 evidence and 164 review records. Actual ARA-capable DAW
  behavior remains an explicit external check.
- Completed the seven-source Q03 A-VSTGUI-RAW review. Q-ABI-001 exposed two
  public C callback payload tags that translated as opaque Zig types. Commit
  `faaf154f` corrects their declaration order and adds native plus three-target
  ReleaseSafe parity for every shared structure, enum, constant, and function
  signature. Current native behavior, visual, LV2 UI, Wayland, ASan/UBSan, and
  four-process TSan gates pass. The ABI ledger now has 144 evidence and 157
  review records. Real DAW embedding and Linux or Windows visual behavior
  remain explicit external checks.
- Completed the three-source Q04 A-VST3-FRAMEWORK review. Existing factory,
  interface, ownership, allocation-failure, reference-saturation, reentrancy,
  host-callback, state, process, and teardown tests cover the raw-to-framework
  boundary. Commit `0382b87f` adds direct lifecycle and precision rejection
  checks plus concurrent topology publication under ThreadSanitizer. Debug and
  ReleaseSafe module gates each pass 800/800 tests, and the Linux ReleaseSafe
  matrix builds all 23 example bundles. The ABI ledger now has 147 evidence
  and 154 review records. Real DAW behavior remains an external check.
- Completed the 16-source Q06 A-RUNTIME review. Plugin declaration validation,
  instance ownership, allocation failure, lifecycle state transitions, dynamic
  topology, host requests, f32 and f64 processing, offline rendering, state,
  realtime auditing, generation rollover, and teardown have direct Debug and
  ReleaseSafe evidence. The exact Q06 sources implement no dynamic-library
  loading or foreign symbol ownership. Those boundaries remain in Q18. The ABI
  ledger now has 163 evidence and 138 review records.
- Completed the nine-source Q17 A-PLUGIN-ABI review against the current split
  LV2 and Audio Unit declaration modules. The LV2 C harness, five loaded host
  fixtures, entry symbols, metadata, bundles, UI lifecycle, and twelve Linux
  and Windows cross-libraries pass. The native AudioToolbox harness, two loaded
  Audio Unit hosts, class-info state, two bundles, and six cross-target outputs
  pass. The ABI ledger now has 172 evidence and 129 review records. Real LV2
  and Audio Unit host behavior remains an external check.

## Phase 5 Scope

- Map critical DSP algorithms to independent numerical vectors, identities,
  or reference implementations with stated tolerances.
- Review finite-value, overflow, precision, latency, channel, layout, and
  transactional-output contracts.
- Record representative setup, realtime, memory, and hostile-scaling
  benchmarks with explicit inputs and regression thresholds.
- Optimize only measured failures while preserving readable invariants and
  numerical evidence.

## Next Review Target

Review the 62-source A-NATIVE family in Q18. Reconcile system audio, MIDI,
windows, schedulers, callback admission and drain, native handles, dynamic
library symbols and unload ordering, failure translation, recovery, and
teardown. Then complete the native VSTGUI adapter review.
